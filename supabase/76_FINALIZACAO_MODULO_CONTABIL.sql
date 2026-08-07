-- 76_FINALIZACAO_MODULO_CONTABIL.sql
-- Fechamento de exercícios, proteção de períodos e histórico de exportações.
begin;

alter table public.contabil_exercicios
  add column if not exists fechado_em timestamptz,
  add column if not exists fechado_por uuid references auth.users(id),
  add column if not exists reaberto_em timestamptz,
  add column if not exists reaberto_por uuid references auth.users(id);

create table if not exists public.contabil_exportacoes (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  exercicio_id uuid references public.contabil_exercicios(id) on delete restrict,
  tipo text not null check (tipo in ('pacote_contabil','apoio_ecf','plano_contas','saldos','lancamentos')),
  leiaute text,
  nome_arquivo text not null,
  hash_conteudo text,
  parametros jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists idx_contabil_exportacoes_empresa on public.contabil_exportacoes(empresa_id, created_at desc);

create or replace function public.validar_exercicio_aberto_lancamento()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_status text; v_inicio date; v_fim date;
begin
  if new.exercicio_id is null then return new; end if;
  select status, data_inicio, data_fim into v_status, v_inicio, v_fim
  from public.contabil_exercicios where id = new.exercicio_id and empresa_id = new.empresa_id;
  if v_status is null then raise exception 'Exercício contábil inválido para esta empresa.'; end if;
  if v_status = 'fechado' then raise exception 'O exercício contábil está fechado.'; end if;
  if new.data < v_inicio or new.data > v_fim then raise exception 'A data do lançamento está fora do exercício selecionado.'; end if;
  return new;
end;
$$;

drop trigger if exists trg_validar_exercicio_aberto_lancamento on public.contabil_lancamentos;
create trigger trg_validar_exercicio_aberto_lancamento
before insert or update of exercicio_id, empresa_id, data on public.contabil_lancamentos
for each row execute function public.validar_exercicio_aberto_lancamento();

create or replace function public.fechar_exercicio_contabil(p_exercicio_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_empresa uuid; v_status text; v_pendencias integer; v_diferenca numeric(14,2);
begin
  select empresa_id, status into v_empresa, v_status from public.contabil_exercicios where id=p_exercicio_id for update;
  if v_empresa is null then raise exception 'Exercício não encontrado.'; end if;
  if not (public.is_master() or (public.is_ativo() and v_empresa=public.current_empresa_id() and public.current_role() in ('admin','tesoureiro'))) then raise exception 'Sem permissão.'; end if;
  if v_status='fechado' then return; end if;
  select count(*) into v_pendencias from public.contabil_lancamentos where exercicio_id=p_exercicio_id and status in ('rascunho','revisao');
  if v_pendencias>0 then raise exception 'Existem % lançamentos pendentes de revisão.', v_pendencias; end if;
  select coalesce(sum(case when p.tipo='debito' then p.valor else -p.valor end),0)
    into v_diferenca from public.contabil_partidas p join public.contabil_lancamentos l on l.id=p.lancamento_id
   where l.exercicio_id=p_exercicio_id and l.status='contabilizado';
  if abs(v_diferenca)>0.009 then raise exception 'O exercício está desequilibrado em %.', v_diferenca; end if;
  update public.contabil_exercicios set status='fechado', fechado_em=now(), fechado_por=auth.uid(), reaberto_em=null, reaberto_por=null where id=p_exercicio_id;
end;
$$;

create or replace function public.reabrir_exercicio_contabil(p_exercicio_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_empresa uuid;
begin
  select empresa_id into v_empresa from public.contabil_exercicios where id=p_exercicio_id for update;
  if v_empresa is null then raise exception 'Exercício não encontrado.'; end if;
  if not (public.is_master() or (public.is_ativo() and v_empresa=public.current_empresa_id() and public.current_role()='admin')) then raise exception 'Somente administrador pode reabrir o exercício.'; end if;
  update public.contabil_exercicios set status='aberto', reaberto_em=now(), reaberto_por=auth.uid() where id=p_exercicio_id;
end;
$$;

alter table public.contabil_exportacoes enable row level security;
drop policy if exists contabil_exportacoes_select on public.contabil_exportacoes;
drop policy if exists contabil_exportacoes_insert on public.contabil_exportacoes;
drop policy if exists contabil_exportacoes_delete on public.contabil_exportacoes;
create policy contabil_exportacoes_select on public.contabil_exportacoes for select using (public.is_master() or (public.is_ativo() and empresa_id=public.current_empresa_id()));
create policy contabil_exportacoes_insert on public.contabil_exportacoes for insert with check (public.is_master() or (public.is_ativo() and empresa_id=public.current_empresa_id() and public.current_role() in ('admin','tesoureiro')));
create policy contabil_exportacoes_delete on public.contabil_exportacoes for delete using (public.is_master() or (public.is_ativo() and empresa_id=public.current_empresa_id() and public.current_role()='admin'));

commit;
