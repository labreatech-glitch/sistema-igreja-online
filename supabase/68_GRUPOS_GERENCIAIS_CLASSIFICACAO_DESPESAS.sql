-- Fase 1: grupos gerenciais e classificação de despesas
-- Migração aditiva: não reclassifica nem altera lançamentos históricos.

create table if not exists public.grupos_gerenciais_despesas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  nome text not null,
  descricao text,
  ordem integer not null default 50,
  ativo boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint grupos_gerenciais_despesas_nome_empresa_key unique (empresa_id, nome)
);

alter table public.categorias_despesas
  add column if not exists grupo_gerencial_id uuid references public.grupos_gerenciais_despesas(id) on delete set null,
  add column if not exists classificacao_padrao text;

alter table public.despesas
  add column if not exists grupo_gerencial_id uuid references public.grupos_gerenciais_despesas(id) on delete set null,
  add column if not exists classificacao text,
  add column if not exists origem_classificacao text;

do $$ begin
  alter table public.categorias_despesas
    add constraint categorias_despesas_classificacao_padrao_check
    check (classificacao_padrao is null or classificacao_padrao in ('fixa','variavel','mista','eventual'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.despesas
    add constraint despesas_classificacao_check
    check (classificacao is null or classificacao in ('fixa','variavel','mista','eventual'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.despesas
    add constraint despesas_origem_classificacao_check
    check (origem_classificacao is null or origem_classificacao in ('categoria','manual','importacao','nao_classificada'));
exception when duplicate_object then null; end $$;

create index if not exists idx_grupos_gerenciais_despesas_empresa on public.grupos_gerenciais_despesas(empresa_id, ativo, ordem);
create index if not exists idx_categorias_despesas_grupo_gerencial on public.categorias_despesas(empresa_id, grupo_gerencial_id);
create index if not exists idx_despesas_grupo_gerencial on public.despesas(empresa_id, grupo_gerencial_id);
create index if not exists idx_despesas_classificacao on public.despesas(empresa_id, classificacao);

alter table public.grupos_gerenciais_despesas enable row level security;

drop policy if exists grupos_gerenciais_despesas_all on public.grupos_gerenciais_despesas;
create policy grupos_gerenciais_despesas_all on public.grupos_gerenciais_despesas
for all
using (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','tesoureiro')))
with check (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in ('admin','tesoureiro')));

-- Proteção adicional contra vínculo entre empresas diferentes.
create or replace function public.validar_grupo_gerencial_despesa_tenant()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  grupo_empresa uuid;
begin
  if new.grupo_gerencial_id is null then return new; end if;
  select empresa_id into grupo_empresa from public.grupos_gerenciais_despesas where id = new.grupo_gerencial_id;
  if grupo_empresa is null or grupo_empresa <> new.empresa_id then
    raise exception 'O grupo gerencial informado não pertence à mesma empresa do registro.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_categorias_validar_grupo_gerencial on public.categorias_despesas;
create trigger trg_categorias_validar_grupo_gerencial
before insert or update of grupo_gerencial_id, empresa_id on public.categorias_despesas
for each row execute function public.validar_grupo_gerencial_despesa_tenant();

drop trigger if exists trg_despesas_validar_grupo_gerencial on public.despesas;
create trigger trg_despesas_validar_grupo_gerencial
before insert or update of grupo_gerencial_id, empresa_id on public.despesas
for each row execute function public.validar_grupo_gerencial_despesa_tenant();

comment on table public.grupos_gerenciais_despesas is 'Agrupamento gerencial de despesas, independente dos grupos da Prestação de Contas.';
comment on column public.categorias_despesas.classificacao_padrao is 'Sugestão para novos lançamentos; não altera despesas históricas.';
comment on column public.despesas.classificacao is 'Classificação registrada no momento do lançamento.';
