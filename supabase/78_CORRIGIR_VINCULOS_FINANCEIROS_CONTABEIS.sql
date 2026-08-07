-- 78_CORRIGIR_VINCULOS_FINANCEIROS_CONTABEIS.sql
-- Corrige o salvamento dos vínculos em perfis master e usuários vinculados à empresa.
-- Usa ROW_COUNT em vez de FOUND após EXECUTE e recebe explicitamente a empresa selecionada.
begin;

create or replace function public.salvar_vinculo_contabil(
  p_tabela text,
  p_registro_id uuid,
  p_conta_contabil_id uuid,
  p_empresa_id uuid
)
returns void
language plpgsql
security definer
set search_path=public, pg_temp
as $$
declare
  v_empresa_perfil uuid := public.current_empresa_id();
  v_empresa_alvo uuid := p_empresa_id;
  v_conta_empresa uuid;
  v_registro_empresa uuid;
  v_analitica boolean;
  v_ativo boolean;
  v_sql text;
  v_rows bigint := 0;
begin
  if auth.uid() is null then
    raise exception 'Sessão não identificada.';
  end if;

  if not (public.is_master() or (public.is_ativo() and public.current_role() in ('admin','tesoureiro'))) then
    raise exception 'Sem permissão para alterar vínculos contábeis.';
  end if;

  if v_empresa_alvo is null then
    raise exception 'Selecione uma empresa antes de salvar o vínculo.';
  end if;

  if not public.is_master() and v_empresa_perfil is distinct from v_empresa_alvo then
    raise exception 'A empresa selecionada não corresponde ao perfil autenticado.';
  end if;

  if p_tabela not in ('categorias_despesas','tipos_receita','tipos_caixa') then
    raise exception 'Cadastro financeiro não permitido para vínculo contábil.';
  end if;

  v_sql := format('select empresa_id from public.%I where id=$1', p_tabela);
  execute v_sql into v_registro_empresa using p_registro_id;
  if v_registro_empresa is null then
    raise exception 'Registro financeiro não encontrado.';
  end if;
  if v_registro_empresa is distinct from v_empresa_alvo then
    raise exception 'O registro financeiro não pertence à empresa selecionada.';
  end if;

  if p_conta_contabil_id is not null then
    select empresa_id, analitica, ativo
      into v_conta_empresa, v_analitica, v_ativo
    from public.contabil_plano_contas
    where id = p_conta_contabil_id;

    if v_conta_empresa is null then
      raise exception 'Conta contábil não encontrada.';
    end if;
    if v_conta_empresa is distinct from v_empresa_alvo then
      raise exception 'A conta contábil não pertence à empresa selecionada.';
    end if;
    if v_ativo is not true then
      raise exception 'A conta contábil está inativa.';
    end if;
    if v_analitica is not true then
      raise exception 'Somente contas analíticas podem receber vínculos.';
    end if;
  end if;

  v_sql := format(
    'update public.%I set conta_contabil_id=$1 where id=$2 and empresa_id=$3',
    p_tabela
  );
  execute v_sql using p_conta_contabil_id, p_registro_id, v_empresa_alvo;
  get diagnostics v_rows = row_count;

  if v_rows <> 1 then
    raise exception 'O vínculo não foi atualizado. Registro alterado por outro processo ou fora do escopo.';
  end if;
end;
$$;

revoke all on function public.salvar_vinculo_contabil(text,uuid,uuid,uuid) from public;
grant execute on function public.salvar_vinculo_contabil(text,uuid,uuid,uuid) to authenticated;

-- Remove a assinatura antiga para impedir chamadas ambíguas e manter uma única regra ativa.
drop function if exists public.salvar_vinculo_contabil(text,uuid,uuid);

commit;
