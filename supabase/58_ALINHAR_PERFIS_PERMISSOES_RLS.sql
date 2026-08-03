-- =========================================================
-- V58 — Alinha perfis operacionais e RLS por modulo
--
-- Objetivo:
--   - Aceitar o perfil interno "membro" em profiles.role.
--   - Manter autocadastro como usuario inativo aguardando aprovacao.
--   - Separar leitura por tenant das operacoes de escrita/exclusao.
--
-- Observacao brownfield:
--   Esta migracao nao remove tabelas, colunas ou dados existentes.
--   Tabelas ausentes ou sem empresa_id sao ignoradas para preservar
--   instalacoes em versoes intermediarias do schema.
-- =========================================================

begin;

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check
  check (role in ('master','admin','gerente','operador','consulta','tesoureiro','secretario','membro'));

drop policy if exists profiles_insert_self on public.profiles;
drop policy if exists profiles_insert_admin on public.profiles;
drop policy if exists profiles_update_admin on public.profiles;

create policy profiles_insert_self on public.profiles for insert
  with check (
    auth.uid() = id
    and ativo = false
    and role in ('secretario','admin','gerente','operador','consulta','tesoureiro','membro')
  );

create policy profiles_insert_admin on public.profiles for insert
  with check (
    public.is_master()
    or (
      public.is_admin()
      and empresa_id = public.current_empresa_id()
      and role <> 'master'
    )
  );

create policy profiles_update_admin on public.profiles for update
  using (
    public.is_master()
    or (public.is_admin() and empresa_id = public.current_empresa_id())
  )
  with check (
    public.is_master()
    or (
      public.is_admin()
      and empresa_id = public.current_empresa_id()
      and role <> 'master'
    )
  );

create or replace function public.apply_role_aligned_tenant_policies(
  p_table text,
  p_write_roles text[],
  p_delete_roles text[]
)
returns void
language plpgsql
as $$
declare
  v_policy record;
  v_table_name text := format('public.%I', p_table);
  v_write_roles text;
  v_delete_roles text;
begin
  if to_regclass(v_table_name) is null then
    return;
  end if;

  if not exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = p_table
       and column_name = 'empresa_id'
  ) then
    return;
  end if;

  select string_agg(quote_literal(role_name), ',')
    into v_write_roles
    from unnest(p_write_roles) as roles(role_name);

  select string_agg(quote_literal(role_name), ',')
    into v_delete_roles
    from unnest(p_delete_roles) as roles(role_name);

  for v_policy in
    select policyname
      from pg_policies
     where schemaname = 'public'
       and tablename = p_table
  loop
    execute format('drop policy if exists %I on public.%I', v_policy.policyname, p_table);
  end loop;

  execute format('alter table public.%I enable row level security', p_table);

  execute format(
    'create policy %I_select on public.%I for select using (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id()))',
    p_table,
    p_table
  );

  execute format(
    'create policy %I_insert on public.%I for insert with check (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in (%s)))',
    p_table,
    p_table,
    v_write_roles
  );

  execute format(
    'create policy %I_update on public.%I for update using (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in (%s))) with check (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in (%s)))',
    p_table,
    p_table,
    v_write_roles,
    v_write_roles
  );

  execute format(
    'create policy %I_delete on public.%I for delete using (public.is_master() or (public.is_ativo() and empresa_id = public.current_empresa_id() and public.current_role() in (%s)))',
    p_table,
    p_table,
    v_delete_roles
  );
end;
$$;

select public.apply_role_aligned_tenant_policies(
  table_name,
  array['admin','gerente','operador','tesoureiro'],
  array['admin','tesoureiro']
)
from unnest(array[
  'tipos_caixa',
  'tipos_receita',
  'categorias_despesas',
  'formas_pagamento',
  'centros_custo',
  'lancamentos_financeiros',
  'despesas',
  'fechamentos_mensais',
  'transferencias_caixas',
  'transferencias_agendadas',
  'bancos',
  'regras_importacao_bancaria',
  'importacoes_bancarias',
  'importacao_bancaria_itens',
  'financeiro_importacoes_planilha',
  'financeiro_importacao_planilha_itens',
  'credores'
]) as t(table_name);

select public.apply_role_aligned_tenant_policies(
  table_name,
  array['admin','gerente','operador','secretario'],
  array['admin','secretario']
)
from unnest(array[
  'membros',
  'membro_historico',
  'familias',
  'filhos_dependentes',
  'congregacoes',
  'ministerios',
  'cargos',
  'setores',
  'profissoes',
  'escolaridades',
  'turmas_ebd',
  'salas_ebd',
  'professores_ebd',
  'turma_professores_ebd',
  'matriculas_ebd',
  'aulas_ebd',
  'frequencia_ebd',
  'patrimonio',
  'patrimonio_categorias',
  'patrimonio_locais',
  'patrimonio_fornecedores',
  'patrimonio_manutencoes'
]) as t(table_name);

select public.apply_role_aligned_tenant_policies(
  table_name,
  array['admin','gerente','secretario'],
  array['admin','secretario']
)
from unnest(array[
  'portal_publicacoes',
  'portal_publicacao_arquivos',
  'portal_eventos',
  'portal_jornadas',
  'portal_chaves_pix'
]) as t(table_name);

drop function if exists public.apply_role_aligned_tenant_policies(text,text[],text[]);

notify pgrst, 'reload schema';
commit;
