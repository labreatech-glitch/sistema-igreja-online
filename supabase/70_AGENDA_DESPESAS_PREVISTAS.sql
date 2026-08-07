-- Fase 4 — agenda controlada de despesas previstas.
-- Previsões ficam separadas do Livro Caixa até confirmação explícita.
begin;
create table if not exists public.despesas_previstas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  referencia text not null,
  data_prevista date not null,
  categoria_id uuid not null references public.categorias_despesas(id) on delete restrict,
  grupo_gerencial_id uuid references public.grupos_gerenciais_despesas(id) on delete set null,
  classificacao text,
  credor_id uuid references public.credores(id) on delete set null,
  tipo_caixa_id uuid references public.tipos_caixa(id) on delete set null,
  descricao text not null,
  valor_previsto numeric(14,2) not null default 0,
  status text not null default 'prevista',
  origem text not null default 'planejamento',
  despesa_id uuid references public.despesas(id) on delete set null,
  confirmada_em timestamptz,
  confirmada_por uuid references auth.users(id),
  cancelada_em timestamptz,
  cancelada_por uuid references auth.users(id),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (empresa_id, referencia, categoria_id)
);
alter table public.despesas add column if not exists despesa_prevista_id uuid references public.despesas_previstas(id) on delete set null;
do $$ begin alter table public.despesas_previstas add constraint despesas_previstas_referencia_check check (referencia ~ '^\d{4}-(0[1-9]|1[0-2])$'); exception when duplicate_object then null; end $$;
do $$ begin alter table public.despesas_previstas add constraint despesas_previstas_status_check check (status in ('prevista','realizada','cancelada')); exception when duplicate_object then null; end $$;
do $$ begin alter table public.despesas_previstas add constraint despesas_previstas_classificacao_check check (classificacao is null or classificacao in ('fixa','variavel','mista','eventual')); exception when duplicate_object then null; end $$;
do $$ begin alter table public.despesas_previstas add constraint despesas_previstas_valor_check check (valor_previsto >= 0); exception when duplicate_object then null; end $$;
create index if not exists idx_despesas_previstas_empresa_referencia on public.despesas_previstas(empresa_id, referencia, status, data_prevista);
create unique index if not exists idx_despesas_despesa_prevista_unique on public.despesas(despesa_prevista_id) where despesa_prevista_id is not null;
alter table public.despesas_previstas enable row level security;
-- Segue o mesmo padrão de autorização das despesas e demais módulos financeiros.
-- Master acessa todas as empresas; admin e tesoureiro acessam somente a empresa ativa.
drop policy if exists despesas_previstas_select_tenant on public.despesas_previstas;
create policy despesas_previstas_select_tenant
on public.despesas_previstas for select
using (
  public.is_master()
  or (
    public.is_ativo()
    and empresa_id = public.current_empresa_id()
    and public.current_role() in ('admin','tesoureiro')
  )
);

drop policy if exists despesas_previstas_insert_tenant on public.despesas_previstas;
create policy despesas_previstas_insert_tenant
on public.despesas_previstas for insert
with check (
  public.is_master()
  or (
    public.is_ativo()
    and empresa_id = public.current_empresa_id()
    and public.current_role() in ('admin','tesoureiro')
  )
);

drop policy if exists despesas_previstas_update_tenant on public.despesas_previstas;
create policy despesas_previstas_update_tenant
on public.despesas_previstas for update
using (
  public.is_master()
  or (
    public.is_ativo()
    and empresa_id = public.current_empresa_id()
    and public.current_role() in ('admin','tesoureiro')
  )
)
with check (
  public.is_master()
  or (
    public.is_ativo()
    and empresa_id = public.current_empresa_id()
    and public.current_role() in ('admin','tesoureiro')
  )
);

drop policy if exists despesas_previstas_delete_tenant on public.despesas_previstas;
create policy despesas_previstas_delete_tenant
on public.despesas_previstas for delete
using (
  public.is_master()
  or (
    public.is_ativo()
    and empresa_id = public.current_empresa_id()
    and public.current_role() in ('admin','tesoureiro')
  )
);
create or replace function public.validar_despesa_prevista_tenant() returns trigger language plpgsql security invoker set search_path=public as $$
declare v_empresa uuid;
begin
  select empresa_id into v_empresa from public.categorias_despesas where id=new.categoria_id;
  if v_empresa is distinct from new.empresa_id then raise exception 'Categoria pertence a outra empresa.'; end if;
  if new.tipo_caixa_id is not null then select empresa_id into v_empresa from public.tipos_caixa where id=new.tipo_caixa_id; if v_empresa is distinct from new.empresa_id then raise exception 'Caixa pertence a outra empresa.'; end if; end if;
  if new.credor_id is not null then select empresa_id into v_empresa from public.credores where id=new.credor_id; if v_empresa is distinct from new.empresa_id then raise exception 'Credor pertence a outra empresa.'; end if; end if;
  return new;
end $$;
drop trigger if exists trg_validar_despesa_prevista_tenant on public.despesas_previstas;
create trigger trg_validar_despesa_prevista_tenant before insert or update of empresa_id,categoria_id,tipo_caixa_id,credor_id on public.despesas_previstas for each row execute function public.validar_despesa_prevista_tenant();
comment on table public.despesas_previstas is 'Agenda separada do Livro Caixa; somente status realizada possui despesa confirmada.';
commit;
