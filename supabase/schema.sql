-- Sistema Igreja Online SaaS Master - RESET LIMPO
-- ATENÇÃO: este script APAGA todos os objetos do schema public e recria o banco do zero.
-- Use em projeto Supabase de desenvolvimento ou quando desejar reconstruir a base.
-- Para executar este reset destrutivo, rode antes na mesma sessão:
--   set app.allow_destructive_schema_reset = 'true';

begin;

do $$
begin
  if coalesce(current_setting('app.allow_destructive_schema_reset', true), '') <> 'true' then
    raise exception 'Reset destrutivo bloqueado. Este script apaga o schema public. Execute primeiro: set app.allow_destructive_schema_reset = ''true'';';
  end if;
end $$;

drop schema if exists public cascade;
create schema public;

grant usage on schema public to postgres, anon, authenticated, service_role;
grant all on schema public to postgres, service_role;
alter default privileges in schema public grant all on tables to postgres, service_role;
alter default privileges in schema public grant all on functions to postgres, service_role;
alter default privileges in schema public grant all on sequences to postgres, service_role;
alter default privileges in schema public grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public grant select on tables to anon;

create extension if not exists "pgcrypto" with schema extensions;

-- =========================================================
-- TABELAS SAAS / MASTER
-- =========================================================
create table public.empresas (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  nome_fantasia text,
  cnpj text,
  telefone text,
  email text,
  endereco text,
  cidade text,
  estado text,
  cep text,
  responsavel text,
  logomarca text,
  cor_menu text default '#1e2a4a',
  ativo boolean not null default true,
  excluida boolean not null default false,
  obs text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid references public.empresas(id) on delete set null,
  nome text not null default '',
  email text not null default '',
  role text not null default 'secretario' check (role in ('master','admin','gerente','operador','consulta','tesoureiro','secretario','membro')),
  ativo boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.assinaturas_planos (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  valor numeric(14,2) not null default 0,
  dias_acesso int not null default 30,
  descricao text,
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.assinaturas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  plano_id uuid references public.assinaturas_planos(id) on delete set null,
  status text not null default 'Teste',
  valor numeric(14,2) not null default 0,
  inicio_em timestamptz not null default now(),
  vencimento_em timestamptz,
  pago_em timestamptz,
  mercado_pago_id text,
  pix_copia_cola text,
  observacoes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.app_configuracoes (
  chave text primary key,
  valor jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table public.logs_auditoria (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid references public.empresas(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,
  acao text not null,
  tabela text,
  registro_id uuid,
  detalhes jsonb default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- =========================================================
-- SECRETARIA
-- =========================================================
create table public.membros (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  numero_membro integer,
  nome text not null,
  endereco text,
  bairro text,
  cidade text,
  cep text,
  uf text,
  telefone_residencial text,
  telefone_celular text,
  data_nascimento date,
  estado_civil text,
  sexo text,
  profissao text,
  setor text,
  congregacao text,
  cargo text,
  complemento text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(empresa_id, numero_membro)
);


create or replace function public.set_numero_membro()
returns trigger
language plpgsql
as $$
begin
  if new.numero_membro is null then
    select coalesce(max(numero_membro), 0) + 1
      into new.numero_membro
      from public.membros
     where empresa_id = new.empresa_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_membros_numero on public.membros;
create trigger trg_membros_numero
before insert on public.membros
for each row execute function public.set_numero_membro();

-- =========================================================
-- EBD
-- =========================================================
create table public.turmas_ebd (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  nome text not null,
  faixa_etaria text,
  professor text,
  sala text,
  dia_semana text,
  horario text,
  ativo boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.matriculas_ebd (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  turma_id uuid not null references public.turmas_ebd(id) on delete cascade,
  membro_id uuid not null references public.membros(id) on delete cascade,
  data_matricula date not null default current_date,
  ativo boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(turma_id, membro_id)
);

create table public.aulas_ebd (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  turma_id uuid not null references public.turmas_ebd(id) on delete cascade,
  data date not null default current_date,
  tema text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(turma_id, data)
);

create table public.frequencia_ebd (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  aula_id uuid not null references public.aulas_ebd(id) on delete cascade,
  membro_id uuid not null references public.membros(id) on delete cascade,
  presente boolean not null default false,
  created_at timestamptz not null default now(),
  unique(aula_id, membro_id)
);

-- =========================================================
-- FINANCEIRO
-- =========================================================
create table public.tipos_caixa (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  nome text not null,
  descricao text,
  ativo boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(empresa_id, nome)
);

create table public.categorias_despesas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  nome text not null,
  ativo boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(empresa_id, nome)
);

create table public.lancamentos_financeiros (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  data date not null default current_date,
  referencia text not null default to_char(current_date, 'YYYY-MM') check (referencia ~ '^[0-9]{4}-[0-9]{2}$'),
  tipo text not null default 'dizimo' check (tipo in ('dizimo','oferta','doacao','outro')),
  membro_id uuid references public.membros(id) on delete set null,
  tipo_caixa_id uuid not null references public.tipos_caixa(id) on delete restrict,
  valor numeric(14,2) not null check (valor >= 0),
  forma_pagamento text not null default 'dinheiro' check (forma_pagamento in ('dinheiro','pix','cartao','transferencia','cheque')),
  culto text,
  observacoes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.despesas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  data date not null default current_date,
  referencia text not null default to_char(current_date, 'YYYY-MM') check (referencia ~ '^[0-9]{4}-[0-9]{2}$'),
  categoria_id uuid references public.categorias_despesas(id) on delete set null,
  tipo_caixa_id uuid not null references public.tipos_caixa(id) on delete restrict,
  descricao text not null,
  valor numeric(14,2) not null check (valor >= 0),
  forma_pagamento text not null default 'dinheiro' check (forma_pagamento in ('dinheiro','pix','cartao','transferencia','cheque')),
  observacoes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.fechamentos_mensais (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  mes int not null check (mes between 1 and 12),
  ano int not null check (ano between 2000 and 2100),
  tipo_caixa_id uuid not null references public.tipos_caixa(id) on delete restrict,
  total_entradas numeric(14,2) not null default 0 check (total_entradas >= 0),
  total_despesas numeric(14,2) not null default 0 check (total_despesas >= 0),
  total_transferencias_entrada numeric(14,2) not null default 0 check (total_transferencias_entrada >= 0),
  total_transferencias_saida numeric(14,2) not null default 0 check (total_transferencias_saida >= 0),
  saldo numeric(14,2) generated always as (coalesce(total_entradas,0) - coalesce(total_despesas,0) + coalesce(total_transferencias_entrada,0) - coalesce(total_transferencias_saida,0)) stored,
  status text not null default 'aberto' check (status in ('aberto','fechado')),
  observacoes text,
  fechado_por uuid references auth.users(id),
  fechado_em timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(empresa_id, mes, ano, tipo_caixa_id)
);

-- =========================================================
-- PATRIMÔNIO
-- =========================================================
create table public.patrimonio_categorias (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  nome text not null,
  descricao text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(empresa_id, nome)
);

create table public.patrimonio_locais (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  nome text not null,
  descricao text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(empresa_id, nome)
);

create table public.patrimonio (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  numero_patrimonio text,
  nome text not null,
  descricao text,
  categoria_id uuid references public.patrimonio_categorias(id) on delete set null,
  local_id uuid references public.patrimonio_locais(id) on delete set null,
  localizacao text,
  status text not null default 'ativo' check (status in ('ativo','manutencao','baixado')),
  valor_aquisicao numeric(14,2) default 0 check (valor_aquisicao >= 0),
  data_aquisicao date,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(empresa_id, numero_patrimonio)
);

create table public.patrimonio_manutencoes (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  patrimonio_id uuid not null references public.patrimonio(id) on delete cascade,
  data_manutencao date not null default current_date,
  tipo text not null default 'preventiva' check (tipo in ('preventiva','corretiva','vistoria','outra')),
  descricao text not null,
  custo numeric(14,2) default 0 check (custo >= 0),
  responsavel text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- =========================================================
-- FUNÇÕES DE SEGURANÇA
-- =========================================================
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.current_role()
returns text
language sql stable security definer
set search_path = public
as $$
  select p.role from public.profiles p where p.id = auth.uid();
$$;

create or replace function public.current_empresa_id()
returns uuid
language sql stable security definer
set search_path = public
as $$
  select p.empresa_id from public.profiles p where p.id = auth.uid();
$$;

create or replace function public.is_master()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce((select p.ativo and (p.role = 'master' or (lower(p.email) in ('labreatech@gmail.com','labreatech@hotmail.com') and lower(p.email) = lower(coalesce(auth.jwt() ->> 'email', '')))) from public.profiles p where p.id = auth.uid()), false);
$$;

create or replace function public.is_ativo()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce((select p.ativo from public.profiles p where p.id = auth.uid()), false);
$$;

create or replace function public.is_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce((select p.ativo and p.role in ('master','admin') from public.profiles p where p.id = auth.uid()), false);
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(coalesce(new.email, ''));
  v_nome text := coalesce(new.raw_user_meta_data->>'nome', new.raw_user_meta_data->>'name', '');
  v_empresa_nome text := nullif(trim(coalesce(new.raw_user_meta_data->>'empresa_nome', '')), '');
  v_empresa_id uuid;
begin
  if v_email in ('labreatech@gmail.com','labreatech@hotmail.com') then
    insert into public.profiles (id, nome, email, role, ativo, empresa_id)
    values (new.id, v_nome, v_email, 'master', true, null)
    on conflict (id) do update set role='master', ativo=true, empresa_id=null, email=excluded.email, updated_at=now();
    return new;
  end if;

  if v_empresa_nome is not null then
    insert into public.empresas (nome, nome_fantasia, email, responsavel, ativo, obs)
    values (v_empresa_nome, v_empresa_nome, v_email, v_nome, true, 'Cadastro criado pela tela pública do SaaS.')
    returning id into v_empresa_id;

    insert into public.assinaturas (empresa_id, status, inicio_em, vencimento_em, valor, observacoes)
    values (v_empresa_id, 'Teste', now(), now() + interval '10 days', 0, 'Teste grátis automático de 10 dias.');

    insert into public.tipos_caixa (empresa_id, nome, descricao)
    values (v_empresa_id, 'Caixa Geral', 'Caixa principal da igreja');

    insert into public.categorias_despesas (empresa_id, nome)
    values (v_empresa_id, 'Água'), (v_empresa_id, 'Energia'), (v_empresa_id, 'Manutenção'), (v_empresa_id, 'Material de expediente');

    insert into public.profiles (id, nome, email, role, ativo, empresa_id)
    values (new.id, v_nome, v_email, 'admin', true, v_empresa_id)
    on conflict (id) do nothing;
  else
    update public.profiles
       set id = new.id,
           nome = coalesce(nullif(nome, ''), v_nome),
           email = v_email,
           updated_at = now()
     where lower(email) = v_email
       and id <> new.id;

    if found then
      return new;
    end if;

    insert into public.profiles (id, nome, email, role, ativo, empresa_id)
    values (new.id, v_nome, v_email, 'secretario', false, null)
    on conflict (id) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- =========================================================
-- VIEWS
-- =========================================================
create view public.vw_saldo_caixas_profissional as
select
  c.empresa_id,
  c.id as caixa_id,
  c.nome as caixa,
  coalesce(e.entradas, 0)::numeric(14,2) as entradas,
  coalesce(s.saidas, 0)::numeric(14,2) as saidas,
  (coalesce(e.entradas, 0) - coalesce(s.saidas, 0))::numeric(14,2) as saldo_atual,
  (coalesce(e.entradas, 0) - coalesce(s.saidas, 0))::numeric(14,2) as saldo
from public.tipos_caixa c
left join (
  select empresa_id, tipo_caixa_id, sum(valor) as entradas
  from public.lancamentos_financeiros
  group by empresa_id, tipo_caixa_id
) e on e.tipo_caixa_id = c.id and e.empresa_id = c.empresa_id
left join (
  select empresa_id, tipo_caixa_id, sum(valor) as saidas
  from public.despesas
  group by empresa_id, tipo_caixa_id
) s on s.tipo_caixa_id = c.id and s.empresa_id = c.empresa_id
where c.ativo = true;

-- =========================================================
-- ÍNDICES
-- =========================================================
create index idx_profiles_email on public.profiles(email);
create unique index if not exists profiles_email_unico_idx on public.profiles (lower(email)) where email is not null and trim(email) <> '';
create index idx_profiles_empresa on public.profiles(empresa_id);
create index idx_empresas_ativo on public.empresas(ativo);
create index idx_assinaturas_empresa on public.assinaturas(empresa_id);
create index idx_membros_empresa on public.membros(empresa_id);
create index idx_membros_nome on public.membros(nome);
create index idx_turmas_empresa on public.turmas_ebd(empresa_id);
create index idx_lancamentos_empresa on public.lancamentos_financeiros(empresa_id);
create index idx_lancamentos_data on public.lancamentos_financeiros(data);
create index idx_lancamentos_referencia on public.lancamentos_financeiros(empresa_id, referencia);
create index idx_lancamentos_caixa on public.lancamentos_financeiros(tipo_caixa_id);
create index idx_despesas_empresa on public.despesas(empresa_id);
create index idx_despesas_data on public.despesas(data);
create index idx_despesas_referencia on public.despesas(empresa_id, referencia);
create index idx_despesas_caixa on public.despesas(tipo_caixa_id);
create index idx_matriculas_turma on public.matriculas_ebd(turma_id);
create index idx_frequencia_aula on public.frequencia_ebd(aula_id);

-- =========================================================
-- TRIGGERS UPDATED_AT
-- =========================================================
create trigger set_empresas_updated_at before update on public.empresas for each row execute function public.set_updated_at();
create trigger set_profiles_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger set_assinaturas_planos_updated_at before update on public.assinaturas_planos for each row execute function public.set_updated_at();
create trigger set_assinaturas_updated_at before update on public.assinaturas for each row execute function public.set_updated_at();
create trigger set_membros_updated_at before update on public.membros for each row execute function public.set_updated_at();
create trigger set_turmas_ebd_updated_at before update on public.turmas_ebd for each row execute function public.set_updated_at();
create trigger set_matriculas_ebd_updated_at before update on public.matriculas_ebd for each row execute function public.set_updated_at();
create trigger set_aulas_ebd_updated_at before update on public.aulas_ebd for each row execute function public.set_updated_at();
create trigger set_tipos_caixa_updated_at before update on public.tipos_caixa for each row execute function public.set_updated_at();
create trigger set_categorias_despesas_updated_at before update on public.categorias_despesas for each row execute function public.set_updated_at();
create trigger set_lancamentos_updated_at before update on public.lancamentos_financeiros for each row execute function public.set_updated_at();
create trigger set_despesas_updated_at before update on public.despesas for each row execute function public.set_updated_at();
create trigger set_fechamentos_updated_at before update on public.fechamentos_mensais for each row execute function public.set_updated_at();
create trigger set_patrimonio_categorias_updated_at before update on public.patrimonio_categorias for each row execute function public.set_updated_at();
create trigger set_patrimonio_locais_updated_at before update on public.patrimonio_locais for each row execute function public.set_updated_at();
create trigger set_patrimonio_updated_at before update on public.patrimonio for each row execute function public.set_updated_at();
create trigger set_patrimonio_manutencoes_updated_at before update on public.patrimonio_manutencoes for each row execute function public.set_updated_at();

-- =========================================================
-- RLS
-- =========================================================
alter table public.empresas enable row level security;
alter table public.profiles enable row level security;
alter table public.assinaturas_planos enable row level security;
alter table public.assinaturas enable row level security;
alter table public.app_configuracoes enable row level security;
alter table public.logs_auditoria enable row level security;
alter table public.membros enable row level security;
alter table public.turmas_ebd enable row level security;
alter table public.matriculas_ebd enable row level security;
alter table public.aulas_ebd enable row level security;
alter table public.frequencia_ebd enable row level security;
alter table public.tipos_caixa enable row level security;
alter table public.categorias_despesas enable row level security;
alter table public.lancamentos_financeiros enable row level security;
alter table public.despesas enable row level security;
alter table public.fechamentos_mensais enable row level security;
alter table public.patrimonio_categorias enable row level security;
alter table public.patrimonio_locais enable row level security;
alter table public.patrimonio enable row level security;
alter table public.patrimonio_manutencoes enable row level security;

-- Profiles
create policy profiles_select on public.profiles for select
  using (auth.uid() = id or public.is_master() or (public.is_admin() and empresa_id = public.current_empresa_id()));
create policy profiles_insert_self on public.profiles for insert
  with check (auth.uid() = id and ativo = false and role in ('secretario','admin','gerente','operador','consulta','tesoureiro','membro') and lower(trim(email)) = lower(trim(coalesce(auth.jwt() ->> 'email', ''))));
create policy profiles_insert_admin on public.profiles for insert
  with check (public.is_master() or (public.is_admin() and empresa_id = public.current_empresa_id() and role <> 'master'));
create policy profiles_update_self_pending on public.profiles for update
  using (auth.uid() = id and ativo = false)
  with check (auth.uid() = id and ativo = false and role in ('secretario','admin','gerente','operador','consulta','tesoureiro','membro') and lower(trim(email)) = lower(trim(coalesce(auth.jwt() ->> 'email', ''))));
create policy profiles_update_admin on public.profiles for update
  using (public.is_master() or (public.is_admin() and empresa_id = public.current_empresa_id()))
  with check (public.is_master() or (public.is_admin() and empresa_id = public.current_empresa_id() and role <> 'master'));

-- Empresas / SaaS
create policy empresas_all_master on public.empresas for all using (public.is_master()) with check (public.is_master());
create policy empresas_select_own on public.empresas for select using (public.is_ativo() and id = public.current_empresa_id());
create policy empresas_update_own_admin on public.empresas for update using (public.is_admin() and id = public.current_empresa_id()) with check (public.is_admin() and id = public.current_empresa_id());

create policy assinaturas_planos_select on public.assinaturas_planos for select using (public.is_ativo());
create policy assinaturas_planos_master on public.assinaturas_planos for all using (public.is_master()) with check (public.is_master());
create policy assinaturas_select on public.assinaturas for select using (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id()));
create policy assinaturas_master on public.assinaturas for all using (public.is_master()) with check (public.is_master());
create policy logs_select_master on public.logs_auditoria for select using (public.is_master() or (public.is_admin() and empresa_id = public.current_empresa_id()));
create policy app_config_select on public.app_configuracoes
for select using (
  public.is_master()
  or (public.is_admin() and chave = ('permissoes_usuarios_' || public.current_empresa_id()::text))
);

create policy app_config_write on public.app_configuracoes
for all using (
  public.is_master()
  or (public.is_admin() and chave = ('permissoes_usuarios_' || public.current_empresa_id()::text))
) with check (
  public.is_master()
  or (public.is_admin() and chave = ('permissoes_usuarios_' || public.current_empresa_id()::text))
);

-- Operacional multiempresa
create policy membros_select on public.membros for select using (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id()));
create policy membros_write on public.membros for all using (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','secretario'))) with check (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','secretario')));

create policy turmas_ebd_all on public.turmas_ebd for all using (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','secretario'))) with check (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','secretario')));
create policy matriculas_ebd_all on public.matriculas_ebd for all using (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','secretario'))) with check (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','secretario')));
create policy aulas_ebd_all on public.aulas_ebd for all using (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','secretario'))) with check (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','secretario')));
create policy frequencia_ebd_all on public.frequencia_ebd for all using (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','secretario'))) with check (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','secretario')));

create policy tipos_caixa_all on public.tipos_caixa for all using (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','tesoureiro'))) with check (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','tesoureiro')));
create policy categorias_despesas_all on public.categorias_despesas for all using (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','tesoureiro'))) with check (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','tesoureiro')));
create policy lancamentos_all on public.lancamentos_financeiros for all using (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','tesoureiro'))) with check (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','tesoureiro')));
create policy despesas_all on public.despesas for all using (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','tesoureiro'))) with check (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','tesoureiro')));
create policy fechamentos_all on public.fechamentos_mensais for all using (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','tesoureiro'))) with check (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','tesoureiro')));

create policy patrimonio_categorias_all on public.patrimonio_categorias for all using (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','secretario'))) with check (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','secretario')));
create policy patrimonio_locais_all on public.patrimonio_locais for all using (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','secretario'))) with check (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','secretario')));
create policy patrimonio_all on public.patrimonio for all using (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','secretario'))) with check (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','secretario')));
create policy patrimonio_manutencoes_all on public.patrimonio_manutencoes for all using (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','secretario'))) with check (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','secretario')));

-- =========================================================
-- SEED DEV
-- =========================================================
insert into public.empresas (nome, nome_fantasia, email, ativo, obs)
values ('Igreja Demonstração', 'Igreja Demo', 'labreatech@gmail.com', true, 'Empresa de demonstração criada pelo reset limpo.');

insert into public.assinaturas_planos (nome, valor, dias_acesso, descricao)
values ('Plano Mensal', 49.90, 30, 'Acesso mensal ao Sistema Igreja Online'),
       ('Plano Anual', 499.90, 365, 'Acesso anual ao Sistema Igreja Online');

insert into public.assinaturas (empresa_id, status, valor, inicio_em, vencimento_em, observacoes)
select id, 'Teste', 0, now(), now() + interval '10 days', 'Teste grátis inicial.' from public.empresas limit 1;

insert into public.tipos_caixa (empresa_id, nome, descricao)
select id, 'Caixa Geral', 'Caixa principal da igreja' from public.empresas limit 1;

insert into public.categorias_despesas (empresa_id, nome)
select e.id, v.nome
from public.empresas e
cross join (values ('Água'), ('Energia'), ('Manutenção'), ('Material de expediente')) v(nome)
limit 4;

-- Promove usuário já existente no Auth como Master Lábrea Tech, se houver.
insert into public.profiles (id, nome, email, role, ativo, empresa_id)
select u.id, coalesce(u.raw_user_meta_data->>'nome', u.raw_user_meta_data->>'name', 'Lábrea Tech'), lower(u.email), 'master', true, null
from auth.users u
where lower(u.email) in ('labreatech@gmail.com','labreatech@hotmail.com')
on conflict (id) do update set role='master', ativo=true, empresa_id=null, email=excluded.email, updated_at=now();

commit;



insert into public.app_configuracoes (chave, valor) values
('permissoes_usuarios', '{"nomenclaturas":{"admin":"Administrador da Igreja","gerente":"Líder / Supervisor","operador":"Operador de Módulo","consulta":"Consulta"},"descricoes":{"admin":"Acesso total ao sistema, configurações e auditoria da igreja.","gerente":"Acompanha módulos, relatórios, financeiro e fechamento.","operador":"Executa lançamentos e cadastros permitidos.","consulta":"Somente visualização, sem alterar dados."},"menus":{"admin":{"dashboard":{"view":true,"create":true,"update":true,"delete":true},"financeiro":{"view":true,"create":true,"update":true,"delete":true},"secretaria":{"view":true,"create":true,"update":true,"delete":true},"ebd":{"view":true,"create":true,"update":true,"delete":true},"patrimonio":{"view":true,"create":true,"update":true,"delete":true},"configuracoes":{"view":true,"create":true,"update":true,"delete":true}},"gerente":{"dashboard":{"view":true},"financeiro":{"view":true,"create":true,"update":true,"delete":false},"secretaria":{"view":true,"create":true,"update":true,"delete":false},"ebd":{"view":true,"create":true,"update":true,"delete":false},"patrimonio":{"view":true,"create":true,"update":true,"delete":false},"configuracoes":{"view":false,"create":false,"update":false,"delete":false}},"operador":{"dashboard":{"view":true},"financeiro":{"view":true,"create":true,"update":false,"delete":false},"secretaria":{"view":true,"create":true,"update":false,"delete":false},"ebd":{"view":true,"create":true,"update":false,"delete":false},"patrimonio":{"view":true,"create":true,"update":false,"delete":false},"configuracoes":{"view":false,"create":false,"update":false,"delete":false}},"consulta":{"dashboard":{"view":true},"financeiro":{"view":true,"create":false,"update":false,"delete":false},"secretaria":{"view":true,"create":false,"update":false,"delete":false},"ebd":{"view":true,"create":false,"update":false,"delete":false},"patrimonio":{"view":true,"create":false,"update":false,"delete":false},"configuracoes":{"view":false,"create":false,"update":false,"delete":false}}},"pagamentos":{"admin":{"Dinheiro":true,"Pix":true,"Cartão":true,"Transferência":true,"Cheque":true},"gerente":{"Dinheiro":true,"Pix":true,"Cartão":true,"Transferência":true,"Cheque":true},"operador":{"Dinheiro":true,"Pix":true,"Cartão":false,"Transferência":false,"Cheque":false},"consulta":{"Dinheiro":false,"Pix":false,"Cartão":false,"Transferência":false,"Cheque":false}}}'::jsonb)
on conflict (chave) do update set valor=excluded.valor, updated_at=now();
