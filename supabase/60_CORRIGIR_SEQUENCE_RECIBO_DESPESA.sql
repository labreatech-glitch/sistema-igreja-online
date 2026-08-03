-- V2.25.0 - Correção de permissão da sequence antiga de recibo de despesa.
--
-- Contexto:
-- Algumas bases antigas ainda podem manter default em despesas.numero_recibo
-- apontando para public.numero_recibo_despesa_seq. Em inserções pelo usuário
-- autenticado, isso causa:
--   permission denied for sequence numero_recibo_despesa_seq
--
-- Correção:
-- 1. Remove defaults antigos baseados em sequence.
-- 2. Reinstala a numeração atual por trigger SECURITY DEFINER.
-- 3. Concede uso nas sequences antigas se elas ainda existirem, por compatibilidade.

begin;

alter table public.lancamentos_financeiros
  add column if not exists numero_recibo bigint,
  add column if not exists numero_recibo_ano integer;

alter table public.despesas
  add column if not exists numero_recibo bigint,
  add column if not exists numero_recibo_ano integer;

alter table public.lancamentos_financeiros
  alter column numero_recibo drop default;

alter table public.despesas
  alter column numero_recibo drop default;

create table if not exists public.recibos_contadores (
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  tipo text not null check (tipo in ('REC','DES')),
  ano integer not null check (ano between 2000 and 2100),
  proximo_numero bigint not null default 1 check (proximo_numero > 0),
  updated_at timestamptz not null default now(),
  primary key (empresa_id, tipo, ano)
);

alter table public.recibos_contadores enable row level security;
revoke all on table public.recibos_contadores from anon, authenticated;

insert into public.recibos_contadores (empresa_id, tipo, ano, proximo_numero)
select empresa_id, 'REC', coalesce(numero_recibo_ano, extract(year from data)::integer), coalesce(max(numero_recibo), 0) + 1
from public.lancamentos_financeiros
where empresa_id is not null
group by empresa_id, coalesce(numero_recibo_ano, extract(year from data)::integer)
on conflict (empresa_id, tipo, ano)
do update
   set proximo_numero = greatest(public.recibos_contadores.proximo_numero, excluded.proximo_numero),
       updated_at = now();

insert into public.recibos_contadores (empresa_id, tipo, ano, proximo_numero)
select empresa_id, 'DES', coalesce(numero_recibo_ano, extract(year from data)::integer), coalesce(max(numero_recibo), 0) + 1
from public.despesas
where empresa_id is not null
group by empresa_id, coalesce(numero_recibo_ano, extract(year from data)::integer)
on conflict (empresa_id, tipo, ano)
do update
   set proximo_numero = greatest(public.recibos_contadores.proximo_numero, excluded.proximo_numero),
       updated_at = now();

create or replace function public.atribuir_numero_recibo_por_igreja()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tipo text := tg_argv[0];
  v_ano integer;
  v_proximo bigint;
begin
  if new.empresa_id is null then
    raise exception 'empresa_id é obrigatório para gerar o número do recibo';
  end if;

  v_ano := extract(year from coalesce(new.data, current_date))::integer;
  new.numero_recibo_ano := coalesce(new.numero_recibo_ano, v_ano);

  if new.numero_recibo is not null then
    return new;
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(new.empresa_id::text || ':' || v_tipo || ':' || new.numero_recibo_ano::text, 0)
  );

  insert into public.recibos_contadores (empresa_id, tipo, ano, proximo_numero)
  values (new.empresa_id, v_tipo, new.numero_recibo_ano, 2)
  on conflict (empresa_id, tipo, ano)
  do update
     set proximo_numero = public.recibos_contadores.proximo_numero + 1,
         updated_at = now()
  returning proximo_numero - 1 into v_proximo;

  new.numero_recibo := v_proximo;
  return new;
end;
$$;

revoke all on function public.atribuir_numero_recibo_por_igreja() from public;
grant execute on function public.atribuir_numero_recibo_por_igreja() to authenticated;

drop trigger if exists trg_lancamentos_numero_recibo_empresa on public.lancamentos_financeiros;
create trigger trg_lancamentos_numero_recibo_empresa
before insert on public.lancamentos_financeiros
for each row execute function public.atribuir_numero_recibo_por_igreja('REC');

drop trigger if exists trg_despesas_numero_recibo_empresa on public.despesas;
create trigger trg_despesas_numero_recibo_empresa
before insert on public.despesas
for each row execute function public.atribuir_numero_recibo_por_igreja('DES');

do $$
begin
  if exists (select 1 from pg_class where relkind = 'S' and relname = 'numero_recibo_seq') then
    grant usage, select, update on sequence public.numero_recibo_seq to authenticated;
  end if;

  if exists (select 1 from pg_class where relkind = 'S' and relname = 'numero_recibo_receita_seq') then
    grant usage, select, update on sequence public.numero_recibo_receita_seq to authenticated;
  end if;

  if exists (select 1 from pg_class where relkind = 'S' and relname = 'numero_recibo_despesa_seq') then
    grant usage, select, update on sequence public.numero_recibo_despesa_seq to authenticated;
  end if;
end $$;

notify pgrst, 'reload schema';

commit;
