-- =========================================================
-- V63 — Gestão patrimonial completa, incremental e multi-tenant
-- Fases 0 a 3: governança, documentos, movimentações, depreciação
-- e inventário. Migração aditiva; não remove bens ou dados existentes.
-- =========================================================

begin;

create extension if not exists pgcrypto;

-- Compatibilidade com bancos históricos em que apenas a tabela `patrimonio`
-- e as estruturas de numeração/histórico foram instaladas. As criações abaixo
-- são aditivas e não substituem nenhuma tabela existente.
create table if not exists public.patrimonio_categorias (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  nome text not null,
  descricao text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(empresa_id,nome)
);

create table if not exists public.patrimonio_locais (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  nome text not null,
  descricao text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(empresa_id,nome)
);

create table if not exists public.patrimonio_manutencoes (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  patrimonio_id uuid not null references public.patrimonio(id) on delete restrict,
  data_manutencao date not null default current_date,
  tipo text not null default 'preventiva' check (tipo in ('preventiva','corretiva','vistoria','outra')),
  descricao text not null,
  custo numeric(14,2) default 0 check (custo>=0),
  responsavel text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Evolução compatível dos cadastros existentes.
alter table public.patrimonio_categorias
  add column if not exists depreciavel boolean not null default false,
  add column if not exists vida_util_meses integer,
  add column if not exists valor_residual_percentual numeric(5,2) not null default 0;

alter table public.patrimonio_categorias drop constraint if exists patrimonio_categorias_vida_util_check;
alter table public.patrimonio_categorias add constraint patrimonio_categorias_vida_util_check
  check (vida_util_meses is null or vida_util_meses > 0);
alter table public.patrimonio_categorias drop constraint if exists patrimonio_categorias_residual_check;
alter table public.patrimonio_categorias add constraint patrimonio_categorias_residual_check
  check (valor_residual_percentual between 0 and 100);

alter table public.patrimonio_locais
  add column if not exists congregacao_id uuid references public.congregacoes(id) on delete set null,
  add column if not exists tipo text not null default 'outro',
  add column if not exists ativo boolean not null default true;

alter table public.patrimonio_locais drop constraint if exists patrimonio_locais_tipo_check;
alter table public.patrimonio_locais add constraint patrimonio_locais_tipo_check
  check (tipo in ('sede','congregacao','sala','ministerio','deposito','outro'));

alter table public.patrimonio
  add column if not exists categoria_id uuid references public.patrimonio_categorias(id) on delete set null,
  add column if not exists local_id uuid references public.patrimonio_locais(id) on delete set null,
  add column if not exists congregacao_id uuid references public.congregacoes(id) on delete set null,
  add column if not exists responsavel_membro_id uuid references public.membros(id) on delete set null,
  add column if not exists despesa_aquisicao_id uuid references public.despesas(id) on delete set null,
  add column if not exists depreciavel boolean,
  add column if not exists vida_util_meses integer,
  add column if not exists valor_residual numeric(14,2) not null default 0,
  add column if not exists depreciacao_inicio date,
  add column if not exists seguro_ate date,
  add column if not exists proxima_manutencao date;

-- Converte os textos de localização já existentes em locais estruturados.
-- O campo legado continua preservado para compatibilidade e conferência.
insert into public.patrimonio_locais(empresa_id,nome,descricao)
select distinct p.empresa_id,trim(p.localizacao),'Migrado da localização histórica do patrimônio'
from public.patrimonio p
where nullif(trim(p.localizacao),'') is not null
on conflict(empresa_id,nome) do nothing;

update public.patrimonio p
set local_id=l.id
from public.patrimonio_locais l
where p.local_id is null
  and l.empresa_id=p.empresa_id
  and l.nome=trim(p.localizacao)
  and nullif(trim(p.localizacao),'') is not null;

alter table public.patrimonio drop constraint if exists patrimonio_vida_util_check;
alter table public.patrimonio add constraint patrimonio_vida_util_check
  check (vida_util_meses is null or vida_util_meses > 0);
alter table public.patrimonio drop constraint if exists patrimonio_valor_residual_check;
alter table public.patrimonio add constraint patrimonio_valor_residual_check
  check (valor_residual >= 0 and valor_residual <= coalesce(valor_aquisicao, valor_residual));

alter table public.patrimonio_manutencoes
  add column if not exists proxima_manutencao date,
  add column if not exists despesa_id uuid references public.despesas(id) on delete set null,
  add column if not exists documento_url text,
  add column if not exists status text not null default 'concluida';

alter table public.patrimonio_manutencoes drop constraint if exists patrimonio_manutencoes_status_check;
alter table public.patrimonio_manutencoes add constraint patrimonio_manutencoes_status_check
  check (status in ('agendada','em_andamento','concluida','cancelada'));
alter table public.patrimonio_manutencoes drop constraint if exists patrimonio_manutencoes_patrimonio_id_fkey;
alter table public.patrimonio_manutencoes add constraint patrimonio_manutencoes_patrimonio_id_fkey
  foreign key (patrimonio_id) references public.patrimonio(id) on delete restrict;

-- Documentos privados por bem: NF, garantia, seguro, foto e termos.
create table if not exists public.patrimonio_documentos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  patrimonio_id uuid not null references public.patrimonio(id) on delete restrict,
  tipo text not null default 'outro' check (tipo in ('nota_fiscal','garantia','seguro','foto','termo','laudo','outro')),
  titulo text not null,
  storage_path text not null,
  nome_original text not null,
  mime_type text,
  tamanho_bytes bigint not null default 0 check (tamanho_bytes >= 0),
  validade_ate date,
  observacoes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(empresa_id, storage_path)
);
alter table public.patrimonio_documentos drop constraint if exists patrimonio_documentos_storage_tenant_check;
alter table public.patrimonio_documentos add constraint patrimonio_documentos_storage_tenant_check
  check (split_part(storage_path,'/',1)=empresa_id::text);

-- Livro formal de movimentações: empréstimo, transferência e baixa.
create table if not exists public.patrimonio_movimentacoes (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  patrimonio_id uuid not null references public.patrimonio(id) on delete restrict,
  tipo text not null check (tipo in ('emprestimo','devolucao','transferencia','baixa','venda','doacao','perda','ajuste')),
  status text not null default 'pendente' check (status in ('rascunho','pendente','aprovado','em_andamento','concluido','rejeitado','cancelado')),
  local_origem_id uuid references public.patrimonio_locais(id) on delete set null,
  local_destino_id uuid references public.patrimonio_locais(id) on delete set null,
  responsavel_membro_id uuid references public.membros(id) on delete set null,
  responsavel_nome text,
  finalidade text,
  justificativa text,
  estado_saida text,
  estado_retorno text,
  data_movimentacao date not null default current_date,
  data_prevista_retorno date,
  data_conclusao date,
  aprovado_por uuid references auth.users(id),
  aprovado_em timestamptz,
  recebido_por uuid references auth.users(id),
  recebido_em timestamptz,
  aceite_nome text,
  aceite_em timestamptz,
  termo_codigo text not null default upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),
  despesa_id uuid references public.despesas(id) on delete set null,
  lancamento_id uuid references public.lancamentos_financeiros(id) on delete set null,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(empresa_id, termo_codigo)
);

-- Fechamentos mensais de depreciação, sem gerar lançamento financeiro automático.
create table if not exists public.patrimonio_depreciacoes (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  patrimonio_id uuid not null references public.patrimonio(id) on delete restrict,
  competencia date not null,
  valor_mensal numeric(14,2) not null default 0 check (valor_mensal >= 0),
  depreciacao_acumulada numeric(14,2) not null default 0 check (depreciacao_acumulada >= 0),
  valor_contabil numeric(14,2) not null default 0 check (valor_contabil >= 0),
  vida_util_meses integer not null check (vida_util_meses > 0),
  valor_residual numeric(14,2) not null default 0 check (valor_residual >= 0),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(empresa_id, patrimonio_id, competencia),
  check (extract(day from competencia)=1)
);

-- Sessões e itens de inventário periódico.
create table if not exists public.patrimonio_inventarios (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  titulo text not null,
  local_id uuid references public.patrimonio_locais(id) on delete set null,
  status text not null default 'aberto' check (status in ('planejado','aberto','concluido','cancelado')),
  data_inicio date not null default current_date,
  data_fim date,
  responsavel text,
  observacoes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.patrimonio_inventario_itens (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  inventario_id uuid not null references public.patrimonio_inventarios(id) on delete cascade,
  patrimonio_id uuid not null references public.patrimonio(id) on delete restrict,
  local_esperado_id uuid references public.patrimonio_locais(id) on delete set null,
  local_encontrado_id uuid references public.patrimonio_locais(id) on delete set null,
  situacao text not null default 'pendente' check (situacao in ('pendente','confirmado','divergente','faltante','sobra')),
  conferido_em timestamptz,
  conferido_por uuid references auth.users(id),
  observacoes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(empresa_id, inventario_id, patrimonio_id)
);

create index if not exists idx_patrimonio_documentos_bem on public.patrimonio_documentos(empresa_id, patrimonio_id, created_at desc);
create index if not exists idx_patrimonio_movimentacoes_bem on public.patrimonio_movimentacoes(empresa_id, patrimonio_id, created_at desc);
create index if not exists idx_patrimonio_movimentacoes_status on public.patrimonio_movimentacoes(empresa_id, status, data_movimentacao desc);
create index if not exists idx_patrimonio_depreciacoes_competencia on public.patrimonio_depreciacoes(empresa_id, competencia desc);
create index if not exists idx_patrimonio_inventarios_status on public.patrimonio_inventarios(empresa_id, status, data_inicio desc);
create index if not exists idx_patrimonio_inventario_itens_situacao on public.patrimonio_inventario_itens(empresa_id, inventario_id, situacao);
create index if not exists idx_patrimonio_categoria on public.patrimonio(empresa_id,categoria_id) where categoria_id is not null;
create index if not exists idx_patrimonio_local on public.patrimonio(empresa_id,local_id) where local_id is not null;
create index if not exists idx_patrimonio_garantia on public.patrimonio(empresa_id, garantia_ate) where garantia_ate is not null;
create index if not exists idx_patrimonio_proxima_manutencao on public.patrimonio(empresa_id, proxima_manutencao) where proxima_manutencao is not null;

drop trigger if exists set_patrimonio_movimentacoes_updated_at on public.patrimonio_movimentacoes;
create trigger set_patrimonio_movimentacoes_updated_at before update on public.patrimonio_movimentacoes
for each row execute function public.set_updated_at();
drop trigger if exists set_patrimonio_inventarios_updated_at on public.patrimonio_inventarios;
create trigger set_patrimonio_inventarios_updated_at before update on public.patrimonio_inventarios
for each row execute function public.set_updated_at();
drop trigger if exists set_patrimonio_inventario_itens_updated_at on public.patrimonio_inventario_itens;
create trigger set_patrimonio_inventario_itens_updated_at before update on public.patrimonio_inventario_itens
for each row execute function public.set_updated_at();
drop trigger if exists set_patrimonio_categorias_updated_at on public.patrimonio_categorias;
create trigger set_patrimonio_categorias_updated_at before update on public.patrimonio_categorias
for each row execute function public.set_updated_at();
drop trigger if exists set_patrimonio_locais_updated_at on public.patrimonio_locais;
create trigger set_patrimonio_locais_updated_at before update on public.patrimonio_locais
for each row execute function public.set_updated_at();
drop trigger if exists set_patrimonio_manutencoes_updated_at on public.patrimonio_manutencoes;
create trigger set_patrimonio_manutencoes_updated_at before update on public.patrimonio_manutencoes
for each row execute function public.set_updated_at();

-- Fase 0: patrimônio nunca é apagado fisicamente; use fluxo de baixa.
create or replace function public.patrimonio_impedir_exclusao()
returns trigger language plpgsql as $$
begin
  raise exception 'Patrimônio não pode ser excluído fisicamente. Registre a baixa para preservar o histórico.';
end;
$$;
drop trigger if exists trg_patrimonio_impedir_exclusao on public.patrimonio;
create trigger trg_patrimonio_impedir_exclusao before delete on public.patrimonio
for each row execute function public.patrimonio_impedir_exclusao();

-- Valida chaves relacionadas contra o mesmo tenant, inclusive quando chamadas
-- por API direta. O frontend não é usado como barreira de segurança.
create or replace function public.patrimonio_validar_tenant_relacionamentos()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare j jsonb:=to_jsonb(new); v uuid;
begin
  if new.empresa_id is null then raise exception 'A igreja/empresa é obrigatória.'; end if;
  v:=nullif(j->>'patrimonio_id','')::uuid;
  if v is not null and not exists(select 1 from public.patrimonio x where x.id=v and x.empresa_id=new.empresa_id) then raise exception 'Bem patrimonial não pertence à igreja informada.'; end if;
  v:=nullif(j->>'categoria_id','')::uuid;
  if v is not null and not exists(select 1 from public.patrimonio_categorias x where x.id=v and x.empresa_id=new.empresa_id) then raise exception 'Categoria patrimonial não pertence à igreja informada.'; end if;
  for v in select value::uuid from jsonb_each_text(j) where key in ('local_id','local_origem_id','local_destino_id','local_esperado_id','local_encontrado_id') and value<>'' loop
    if not exists(select 1 from public.patrimonio_locais x where x.id=v and x.empresa_id=new.empresa_id) then raise exception 'Local patrimonial não pertence à igreja informada.'; end if;
  end loop;
  v:=nullif(j->>'congregacao_id','')::uuid;
  if v is not null and not exists(select 1 from public.congregacoes x where x.id=v and x.empresa_id=new.empresa_id) then raise exception 'Congregação não pertence à igreja informada.'; end if;
  v:=nullif(j->>'responsavel_membro_id','')::uuid;
  if v is not null and not exists(select 1 from public.membros x where x.id=v and x.empresa_id=new.empresa_id) then raise exception 'Membro responsável não pertence à igreja informada.'; end if;
  for v in select value::uuid from jsonb_each_text(j) where key in ('despesa_id','despesa_aquisicao_id') and value<>'' loop
    if not exists(select 1 from public.despesas x where x.id=v and x.empresa_id=new.empresa_id) then raise exception 'Despesa vinculada não pertence à igreja informada.'; end if;
  end loop;
  v:=nullif(j->>'lancamento_id','')::uuid;
  if v is not null and not exists(select 1 from public.lancamentos_financeiros x where x.id=v and x.empresa_id=new.empresa_id) then raise exception 'Receita vinculada não pertence à igreja informada.'; end if;
  v:=nullif(j->>'inventario_id','')::uuid;
  if v is not null and not exists(select 1 from public.patrimonio_inventarios x where x.id=v and x.empresa_id=new.empresa_id) then raise exception 'Inventário não pertence à igreja informada.'; end if;
  return new;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['patrimonio','patrimonio_locais','patrimonio_manutencoes','patrimonio_documentos','patrimonio_movimentacoes','patrimonio_depreciacoes','patrimonio_inventarios','patrimonio_inventario_itens'] loop
    execute format('drop trigger if exists trg_%I_tenant_rel on public.%I',t,t);
    execute format('create trigger trg_%I_tenant_rel before insert or update on public.%I for each row execute function public.patrimonio_validar_tenant_relacionamentos()',t,t);
  end loop;
end $$;

-- Status de baixa, movimentação e fechamento de inventário só mudam pelas
-- funções transacionais abaixo; aceite e conferência continuam editáveis.
create or replace function public.patrimonio_proteger_fluxo_formal()
returns trigger language plpgsql set search_path=public as $$
begin
  if tg_table_name='patrimonio_movimentacoes' and old.status is distinct from new.status and coalesce(current_setting('app.patrimonio_workflow',true),'')<>'1' then
    raise exception 'Use a ação formal de aprovar/concluir movimentação.';
  elsif tg_table_name='patrimonio_inventarios' and old.status is distinct from new.status and coalesce(current_setting('app.patrimonio_inventory_workflow',true),'')<>'1' then
    raise exception 'Use a ação formal de concluir inventário.';
  elsif tg_table_name='patrimonio' and old.status is distinct from new.status and new.status='baixado' and coalesce(current_setting('app.patrimonio_workflow',true),'')<>'1' then
    raise exception 'Registre e aprove a baixa no menu Movimentações.';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_patrimonio_fluxo_formal on public.patrimonio;
create trigger trg_patrimonio_fluxo_formal before update on public.patrimonio for each row execute function public.patrimonio_proteger_fluxo_formal();
drop trigger if exists trg_patrimonio_movimentacoes_fluxo_formal on public.patrimonio_movimentacoes;
create trigger trg_patrimonio_movimentacoes_fluxo_formal before update on public.patrimonio_movimentacoes for each row execute function public.patrimonio_proteger_fluxo_formal();
drop trigger if exists trg_patrimonio_inventarios_fluxo_formal on public.patrimonio_inventarios;
create trigger trg_patrimonio_inventarios_fluxo_formal before update on public.patrimonio_inventarios for each row execute function public.patrimonio_proteger_fluxo_formal();

alter table public.patrimonio_historico drop constraint if exists patrimonio_historico_patrimonio_id_fkey;
alter table public.patrimonio_historico add constraint patrimonio_historico_patrimonio_id_fkey
  foreign key (patrimonio_id) references public.patrimonio(id) on delete restrict;

-- Aplica isolamento por igreja e escrita compatível com os perfis atuais.
alter table public.patrimonio_documentos enable row level security;
alter table public.patrimonio_movimentacoes enable row level security;
alter table public.patrimonio_depreciacoes enable row level security;
alter table public.patrimonio_inventarios enable row level security;
alter table public.patrimonio_inventario_itens enable row level security;
alter table public.patrimonio_categorias enable row level security;
alter table public.patrimonio_locais enable row level security;
alter table public.patrimonio_manutencoes enable row level security;
do $$
declare t text; p record;
begin
  foreach t in array array['patrimonio_categorias','patrimonio_locais','patrimonio_manutencoes','patrimonio_documentos','patrimonio_movimentacoes','patrimonio_depreciacoes','patrimonio_inventarios','patrimonio_inventario_itens'] loop
    execute format('alter table public.%I enable row level security', t);
    for p in select policyname from pg_policies where schemaname='public' and tablename=t loop
      execute format('drop policy if exists %I on public.%I', p.policyname, t);
    end loop;
    execute format('create policy %I_select on public.%I for select using (public.is_master() or (public.is_ativo() and empresa_id=public.current_empresa_id()))', t, t);
    execute format('create policy %I_insert on public.%I for insert with check (public.is_master() or (public.is_ativo() and empresa_id=public.current_empresa_id() and public.current_role() in (''admin'',''gerente'',''operador'',''secretario'')))', t, t);
    execute format('create policy %I_update on public.%I for update using (public.is_master() or (public.is_ativo() and empresa_id=public.current_empresa_id() and public.current_role() in (''admin'',''gerente'',''secretario''))) with check (public.is_master() or (public.is_ativo() and empresa_id=public.current_empresa_id() and public.current_role() in (''admin'',''gerente'',''secretario'')))', t, t);
    execute format('create policy %I_delete on public.%I for delete using (public.is_master() or (public.is_ativo() and empresa_id=public.current_empresa_id() and public.current_role() in (''admin'',''secretario'')))', t, t);
  end loop;
end $$;

-- O operador pode executar a conferência, mas não concluir a sessão nem
-- alterar o status das movimentações.
drop policy if exists patrimonio_inventario_itens_update on public.patrimonio_inventario_itens;
create policy patrimonio_inventario_itens_update on public.patrimonio_inventario_itens for update
using (public.is_master() or (public.is_ativo() and empresa_id=public.current_empresa_id() and public.current_role() in ('admin','gerente','operador','secretario')))
with check (public.is_master() or (public.is_ativo() and empresa_id=public.current_empresa_id() and public.current_role() in ('admin','gerente','operador','secretario')));

-- Remove qualquer política de DELETE do bem; o trigger permanece como segunda barreira.
drop policy if exists patrimonio_delete on public.patrimonio;
create policy patrimonio_delete on public.patrimonio for delete using (false);

-- Arquivos privados: pasta inicial obrigatoriamente igual ao tenant.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('patrimonio-documentos','patrimonio-documentos',false,10485760,
  array['application/pdf','image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists patrimonio_documentos_storage_select on storage.objects;
drop policy if exists patrimonio_documentos_storage_insert on storage.objects;
drop policy if exists patrimonio_documentos_storage_update on storage.objects;
drop policy if exists patrimonio_documentos_storage_delete on storage.objects;
create policy patrimonio_documentos_storage_select on storage.objects for select to authenticated using (
  bucket_id='patrimonio-documentos' and (public.is_master() or (public.is_ativo() and (storage.foldername(name))[1]=public.current_empresa_id()::text))
);
create policy patrimonio_documentos_storage_insert on storage.objects for insert to authenticated with check (
  bucket_id='patrimonio-documentos' and (public.is_master() or (public.is_ativo() and public.current_role() in ('admin','gerente','operador','secretario') and (storage.foldername(name))[1]=public.current_empresa_id()::text))
);
create policy patrimonio_documentos_storage_update on storage.objects for update to authenticated using (
  bucket_id='patrimonio-documentos' and (public.is_master() or (public.is_ativo() and public.current_role() in ('admin','gerente','secretario') and (storage.foldername(name))[1]=public.current_empresa_id()::text))
) with check (
  bucket_id='patrimonio-documentos' and (public.is_master() or (public.is_ativo() and public.current_role() in ('admin','gerente','secretario') and (storage.foldername(name))[1]=public.current_empresa_id()::text))
);
create policy patrimonio_documentos_storage_delete on storage.objects for delete to authenticated using (
  bucket_id='patrimonio-documentos' and (public.is_master() or (public.is_ativo() and public.current_role() in ('admin','secretario') and (storage.foldername(name))[1]=public.current_empresa_id()::text))
);

-- Processa aprovação/conclusão junto com o estado do bem na mesma transação.
create or replace function public.patrimonio_processar_movimentacao(p_movimentacao_id uuid, p_acao text)
returns public.patrimonio_movimentacoes
language plpgsql
security definer
set search_path=public
as $$
declare
  v public.patrimonio_movimentacoes%rowtype;
  v_responsavel text;
begin
  select * into v from public.patrimonio_movimentacoes where id=p_movimentacao_id for update;
  if v.id is null then raise exception 'Movimentação não encontrada.'; end if;
  if not public.is_master() and (not public.is_ativo() or v.empresa_id<>public.current_empresa_id() or public.current_role() not in ('admin','gerente','secretario')) then
    raise exception 'Perfil sem permissão para processar movimentações patrimoniais.';
  end if;

  if p_acao='aprovar' then
    if v.status<>'pendente' then raise exception 'Somente movimentações pendentes podem ser aprovadas.'; end if;
    perform set_config('app.patrimonio_workflow','1',true);
    update public.patrimonio_movimentacoes set status='aprovado',aprovado_por=auth.uid(),aprovado_em=now() where id=v.id returning * into v;
    if v.tipo='emprestimo' then
      select nome into v_responsavel from public.membros where id=v.responsavel_membro_id and empresa_id=v.empresa_id;
      update public.patrimonio set status='emprestado',responsavel=coalesce(v_responsavel,v.responsavel_nome),responsavel_membro_id=v.responsavel_membro_id where id=v.patrimonio_id and empresa_id=v.empresa_id;
    end if;
  elsif p_acao='concluir' then
    if v.status not in ('aprovado','em_andamento') then raise exception 'A movimentação precisa estar aprovada ou em andamento.'; end if;
    perform set_config('app.patrimonio_workflow','1',true);
    update public.patrimonio_movimentacoes set status='concluido',data_conclusao=current_date,recebido_por=auth.uid(),recebido_em=now() where id=v.id returning * into v;
    if v.tipo in ('emprestimo','devolucao') then
      update public.patrimonio set status='ativo',responsavel=null,responsavel_membro_id=null where id=v.patrimonio_id and empresa_id=v.empresa_id;
    elsif v.tipo='transferencia' then
      if v.local_destino_id is null then raise exception 'A transferência não possui local de destino.'; end if;
      update public.patrimonio set local_id=v.local_destino_id,status='ativo' where id=v.patrimonio_id and empresa_id=v.empresa_id;
    elsif v.tipo in ('baixa','venda','doacao') then
      update public.patrimonio set status='baixado',data_baixa=current_date,motivo_baixa=case v.tipo when 'baixa' then 'Baixa' when 'venda' then 'Venda' else 'Doação' end||': '||coalesce(v.justificativa,'sem complemento') where id=v.patrimonio_id and empresa_id=v.empresa_id;
    elsif v.tipo='perda' then
      update public.patrimonio set status='extraviado',motivo_baixa=v.justificativa where id=v.patrimonio_id and empresa_id=v.empresa_id;
    end if;
  else
    raise exception 'Ação patrimonial inválida.';
  end if;
  return v;
end;
$$;

-- Cria a sessão e sua fotografia de itens esperados atomicamente.
create or replace function public.patrimonio_abrir_inventario(
  p_empresa_id uuid, p_titulo text, p_local_id uuid default null, p_data_inicio date default current_date,
  p_responsavel text default null, p_observacoes text default null
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare v_id uuid;
begin
  if not public.is_master() and (not public.is_ativo() or p_empresa_id<>public.current_empresa_id() or public.current_role() not in ('admin','gerente','operador','secretario')) then
    raise exception 'Perfil sem permissão para abrir inventário patrimonial.';
  end if;
  if nullif(trim(p_titulo),'') is null then raise exception 'Informe o título do inventário.'; end if;
  insert into public.patrimonio_inventarios(empresa_id,titulo,local_id,status,data_inicio,responsavel,observacoes,created_by)
  values(p_empresa_id,trim(p_titulo),p_local_id,'aberto',coalesce(p_data_inicio,current_date),nullif(trim(p_responsavel),''),nullif(trim(p_observacoes),''),auth.uid()) returning id into v_id;
  insert into public.patrimonio_inventario_itens(empresa_id,inventario_id,patrimonio_id,local_esperado_id)
  select p.empresa_id,v_id,p.id,p.local_id from public.patrimonio p
  where p.empresa_id=p_empresa_id and p.status<>'baixado' and (p_local_id is null or p.local_id=p_local_id);
  return v_id;
end;
$$;

create or replace function public.patrimonio_concluir_inventario(p_inventario_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_empresa_id uuid; v_status text;
begin
  select empresa_id,status into v_empresa_id,v_status from public.patrimonio_inventarios where id=p_inventario_id for update;
  if v_empresa_id is null then raise exception 'Inventário não encontrado.'; end if;
  if not public.is_master() and (not public.is_ativo() or v_empresa_id<>public.current_empresa_id() or public.current_role() not in ('admin','gerente','secretario')) then
    raise exception 'Perfil sem permissão para concluir inventário patrimonial.';
  end if;
  if v_status<>'aberto' then raise exception 'Somente inventários abertos podem ser concluídos.'; end if;
  perform set_config('app.patrimonio_inventory_workflow','1',true);
  update public.patrimonio_inventario_itens set situacao='faltante' where inventario_id=p_inventario_id and situacao='pendente';
  update public.patrimonio_inventarios set status='concluido',data_fim=current_date where id=p_inventario_id;
end;
$$;

revoke all on function public.patrimonio_processar_movimentacao(uuid,text) from public, anon;
revoke all on function public.patrimonio_abrir_inventario(uuid,text,uuid,date,text,text) from public, anon;
revoke all on function public.patrimonio_concluir_inventario(uuid) from public, anon;
revoke all on function public.patrimonio_validar_tenant_relacionamentos() from public, anon;
revoke all on function public.patrimonio_proteger_fluxo_formal() from public, anon;
grant execute on function public.patrimonio_processar_movimentacao(uuid,text) to authenticated;
grant execute on function public.patrimonio_abrir_inventario(uuid,text,uuid,date,text,text) to authenticated;
grant execute on function public.patrimonio_concluir_inventario(uuid) to authenticated;

-- Auditoria genérica também cobre as novas tabelas quando a função V16 existe.
do $$
declare t text;
begin
  if to_regprocedure('public.audit_trigger_fn()') is not null then
    foreach t in array array['patrimonio_categorias','patrimonio_locais','patrimonio_manutencoes','patrimonio_documentos','patrimonio_movimentacoes','patrimonio_depreciacoes','patrimonio_inventarios','patrimonio_inventario_itens'] loop
      execute format('drop trigger if exists trg_audit_%I on public.%I', t, t);
      execute format('create trigger trg_audit_%I after insert or update or delete on public.%I for each row execute function public.audit_trigger_fn()', t, t);
    end loop;
  end if;
end $$;

notify pgrst, 'reload schema';
commit;

-- Validação pós-migração sugerida:
-- select to_regclass('public.patrimonio_movimentacoes'), to_regclass('public.patrimonio_inventarios');
-- select relrowsecurity from pg_class where oid='public.patrimonio_movimentacoes'::regclass;
