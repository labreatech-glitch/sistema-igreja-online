-- 74_BASE_MODULO_CONTABIL.sql
-- Base contábil aditiva e multi-tenant. Não gera ECD/ECF e não reclassifica dados históricos.
begin;

create table if not exists public.contabil_exercicios (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  ano integer not null check (ano between 2000 and 2100),
  descricao text,
  data_inicio date not null,
  data_fim date not null,
  status text not null default 'aberto' check (status in ('aberto','fechado')),
  fechado_em timestamptz,
  fechado_por uuid references auth.users(id),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint contabil_exercicios_periodo_valido check (data_fim >= data_inicio),
  unique (empresa_id, ano)
);

create table if not exists public.contabil_contas_referenciais (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  codigo text not null,
  nome text not null,
  versao_leiaute text not null,
  ano_inicio integer,
  ano_fim integer,
  ativo boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (empresa_id, codigo, versao_leiaute)
);

create table if not exists public.contabil_plano_contas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  codigo text not null,
  nome text not null,
  conta_pai_id uuid references public.contabil_plano_contas(id) on delete restrict,
  tipo text not null check (tipo in ('ativo','passivo','patrimonio_social','receita','despesa','compensacao')),
  natureza text not null check (natureza in ('devedora','credora')),
  analitica boolean not null default true,
  conta_referencial_id uuid references public.contabil_contas_referenciais(id) on delete set null,
  vigencia_inicio date,
  vigencia_fim date,
  observacoes text,
  ativo boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint contabil_plano_vigencia_valida check (vigencia_fim is null or vigencia_inicio is null or vigencia_fim >= vigencia_inicio),
  constraint contabil_plano_nao_autorreferencia check (conta_pai_id is null or conta_pai_id <> id),
  unique (empresa_id, codigo)
);

create table if not exists public.contabil_configuracoes (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  natureza_juridica text not null,
  situacao_tributaria text check (situacao_tributaria in ('imune','isenta','outra')),
  tipo_imunidade_isencao text,
  contador_nome text,
  contador_cpf text,
  contador_crc text,
  escritorio_cnpj text,
  responsavel_legal_nome text,
  responsavel_legal_cpf text,
  entrega_ecd boolean not null default false,
  possui_cebas boolean not null default false,
  observacoes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (empresa_id)
);

alter table public.categorias_despesas add column if not exists conta_contabil_id uuid references public.contabil_plano_contas(id) on delete set null;
alter table public.tipos_receita add column if not exists conta_contabil_id uuid references public.contabil_plano_contas(id) on delete set null;
alter table public.tipos_caixa add column if not exists conta_contabil_id uuid references public.contabil_plano_contas(id) on delete set null;

create index if not exists idx_contabil_exercicios_empresa on public.contabil_exercicios(empresa_id, ano);
create index if not exists idx_contabil_plano_empresa_codigo on public.contabil_plano_contas(empresa_id, codigo);
create index if not exists idx_contabil_plano_pai on public.contabil_plano_contas(conta_pai_id);
create index if not exists idx_contabil_referenciais_empresa on public.contabil_contas_referenciais(empresa_id, versao_leiaute, codigo);
create index if not exists idx_categoria_despesa_conta_contabil on public.categorias_despesas(conta_contabil_id);
create index if not exists idx_tipo_receita_conta_contabil on public.tipos_receita(conta_contabil_id);
create index if not exists idx_tipo_caixa_conta_contabil on public.tipos_caixa(conta_contabil_id);

-- Protege vínculo cruzado entre empresas.
create or replace function public.validar_vinculo_contabil_mesma_empresa()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare conta_empresa uuid;
begin
  if new.conta_contabil_id is null then return new; end if;
  select empresa_id into conta_empresa from public.contabil_plano_contas where id = new.conta_contabil_id;
  if conta_empresa is null or conta_empresa <> new.empresa_id then
    raise exception 'A conta contábil deve pertencer à mesma empresa do cadastro financeiro.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_categoria_despesa_conta_empresa on public.categorias_despesas;
create trigger trg_categoria_despesa_conta_empresa before insert or update of conta_contabil_id, empresa_id on public.categorias_despesas for each row execute function public.validar_vinculo_contabil_mesma_empresa();
drop trigger if exists trg_tipo_receita_conta_empresa on public.tipos_receita;
create trigger trg_tipo_receita_conta_empresa before insert or update of conta_contabil_id, empresa_id on public.tipos_receita for each row execute function public.validar_vinculo_contabil_mesma_empresa();
drop trigger if exists trg_tipo_caixa_conta_empresa on public.tipos_caixa;
create trigger trg_tipo_caixa_conta_empresa before insert or update of conta_contabil_id, empresa_id on public.tipos_caixa for each row execute function public.validar_vinculo_contabil_mesma_empresa();

-- RLS no mesmo padrão do sistema existente.
do $$
declare t text;
begin
  foreach t in array array['contabil_exercicios','contabil_contas_referenciais','contabil_plano_contas','contabil_configuracoes'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format('drop policy if exists %I on public.%I', t || '_insert', t);
    execute format('drop policy if exists %I on public.%I', t || '_update', t);
    execute format('drop policy if exists %I on public.%I', t || '_delete', t);
    execute format('create policy %I on public.%I for select using (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id()))', t || '_select', t);
    execute format('create policy %I on public.%I for insert with check (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in (''admin'',''tesoureiro'')))', t || '_insert', t);
    execute format('create policy %I on public.%I for update using (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in (''admin'',''tesoureiro''))) with check (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in (''admin'',''tesoureiro'')))', t || '_update', t);
    execute format('create policy %I on public.%I for delete using (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() = ''admin''))', t || '_delete', t);
  end loop;
end $$;

-- Estrutura sintética mínima, somente para orientar o início. Deve ser revisada pelo contador.
insert into public.contabil_plano_contas (empresa_id, codigo, nome, tipo, natureza, analitica, observacoes)
select e.id, x.codigo, x.nome, x.tipo, x.natureza, false, 'Estrutura inicial sugerida. Validar com o contador responsável.'
from public.empresas e
cross join (values
  ('1','ATIVO','ativo','devedora'),
  ('2','PASSIVO','passivo','credora'),
  ('3','PATRIMÔNIO SOCIAL','patrimonio_social','credora'),
  ('4','RECEITAS','receita','credora'),
  ('5','DESPESAS','despesa','devedora'),
  ('9','CONTAS DE COMPENSAÇÃO','compensacao','devedora')
) as x(codigo,nome,tipo,natureza)
on conflict (empresa_id, codigo) do nothing;

commit;
