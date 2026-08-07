-- Fase 2 — parâmetros de recorrência e planejamento por categoria.
-- Migração aditiva: não gera despesas e não altera registros históricos.
begin;

alter table public.categorias_despesas
  add column if not exists recorrente_padrao boolean not null default false,
  add column if not exists incluir_previsao_padrao boolean not null default false,
  add column if not exists periodicidade_padrao text,
  add column if not exists dia_vencimento_padrao integer,
  add column if not exists mes_vencimento_padrao integer,
  add column if not exists valor_previsto_padrao numeric(14,2),
  add column if not exists parcela_fixa_prevista numeric(14,2),
  add column if not exists tolerancia_variacao_percentual numeric(7,2),
  add column if not exists tipo_caixa_padrao_id uuid references public.tipos_caixa(id) on delete set null,
  add column if not exists credor_padrao_id uuid references public.credores(id) on delete set null;

do $$ begin
  alter table public.categorias_despesas add constraint categorias_periodicidade_padrao_check
    check (periodicidade_padrao is null or periodicidade_padrao in ('mensal','trimestral','semestral','anual'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.categorias_despesas add constraint categorias_dia_vencimento_padrao_check
    check (dia_vencimento_padrao is null or dia_vencimento_padrao between 1 and 31);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.categorias_despesas add constraint categorias_mes_vencimento_padrao_check
    check (mes_vencimento_padrao is null or mes_vencimento_padrao between 1 and 12);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.categorias_despesas add constraint categorias_valores_planejamento_check
    check ((valor_previsto_padrao is null or valor_previsto_padrao >= 0)
       and (parcela_fixa_prevista is null or parcela_fixa_prevista >= 0)
       and (tolerancia_variacao_percentual is null or tolerancia_variacao_percentual >= 0));
exception when duplicate_object then null; end $$;

create index if not exists idx_categorias_despesas_planejamento
  on public.categorias_despesas(empresa_id, incluir_previsao_padrao, recorrente_padrao, periodicidade_padrao);

create or replace function public.validar_planejamento_categoria_tenant()
returns trigger language plpgsql security invoker set search_path = public as $$
declare caixa_empresa uuid; credor_empresa uuid;
begin
  if new.tipo_caixa_padrao_id is not null then
    select empresa_id into caixa_empresa from public.tipos_caixa where id = new.tipo_caixa_padrao_id;
    if caixa_empresa is distinct from new.empresa_id then raise exception 'Caixa padrão pertence a outra empresa.'; end if;
  end if;
  if new.credor_padrao_id is not null then
    select empresa_id into credor_empresa from public.credores where id = new.credor_padrao_id;
    if credor_empresa is distinct from new.empresa_id then raise exception 'Credor padrão pertence a outra empresa.'; end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_categorias_validar_planejamento_tenant on public.categorias_despesas;
create trigger trg_categorias_validar_planejamento_tenant before insert or update of empresa_id, tipo_caixa_padrao_id, credor_padrao_id
on public.categorias_despesas for each row execute function public.validar_planejamento_categoria_tenant();

comment on column public.categorias_despesas.incluir_previsao_padrao is 'Inclui a categoria no painel de previsão; não gera lançamento financeiro.';
comment on column public.categorias_despesas.valor_previsto_padrao is 'Valor base opcional para previsão. Histórico não é reclassificado.';
commit;
