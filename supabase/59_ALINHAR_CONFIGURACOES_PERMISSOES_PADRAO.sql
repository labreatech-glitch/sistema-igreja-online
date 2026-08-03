-- =========================================================
-- V59 - Alinha configuracoes persistidas de permissoes
--
-- Objetivo:
--   Completar app_configuracoes.valor com os perfis e blocos padrao atuais
--   sem sobrescrever escolhas ja personalizadas por cada igreja.
--
-- Preservacao:
--   Esta migracao nao apaga dados. O merge profundo mantem valores existentes
--   e adiciona somente chaves ausentes em menus, dashboard, pagamentos,
--   financeiro, nomenclaturas e descricoes.
-- =========================================================

begin;

create or replace function public.jsonb_apply_permission_defaults_v59(
  p_value jsonb,
  p_defaults jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb := coalesce(p_value, '{}'::jsonb);
  v_key text;
  v_default_value jsonb;
  v_current_value jsonb;
begin
  if jsonb_typeof(v_result) <> 'object' or jsonb_typeof(p_defaults) <> 'object' then
    return coalesce(p_value, p_defaults);
  end if;

  for v_key, v_default_value in
    select key, value from jsonb_each(p_defaults)
  loop
    v_current_value := v_result -> v_key;

    if v_current_value is null then
      v_result := v_result || jsonb_build_object(v_key, v_default_value);
    elsif jsonb_typeof(v_current_value) = 'object' and jsonb_typeof(v_default_value) = 'object' then
      v_result := jsonb_set(
        v_result,
        array[v_key],
        public.jsonb_apply_permission_defaults_v59(v_current_value, v_default_value),
        true
      );
    end if;
  end loop;

  return v_result;
end;
$$;

do $$
declare
  v_defaults jsonb := $permissoes$
{
  "nomenclaturas": {
    "admin": "Administrador da Igreja",
    "gerente": "Lider / Supervisor",
    "secretario": "Secretário",
    "tesoureiro": "Tesoureiro",
    "operador": "Operador de Módulo",
    "consulta": "Consulta",
    "membro": "Membro"
  },
  "descricoes": {
    "admin": "Acesso total ao sistema, configuracoes e auditoria da igreja.",
    "gerente": "Acompanha operacao, relatorios, financeiro e fechamento.",
    "secretario": "Gerencia secretaria, EBD, patrimonio e cadastros administrativos.",
    "tesoureiro": "Gerencia financeiro, caixas, lancamentos, importacoes e fechamento.",
    "operador": "Executa lancamentos diarios e cadastros permitidos.",
    "consulta": "Somente visualizacao, sem alterar dados operacionais.",
    "membro": "Acesso pessoal ao portal, agenda, jornadas e contribuicoes."
  },
  "menus": {
    "admin": {
      "dashboard": {"view": true, "create": true, "update": true, "delete": true},
      "financeiro": {"view": true, "create": true, "update": true, "delete": true},
      "secretaria": {"view": true, "create": true, "update": true, "delete": true},
      "ebd": {"view": true, "create": true, "update": true, "delete": true},
      "patrimonio": {"view": true, "create": true, "update": true, "delete": true},
      "portal": {"view": true, "create": true, "update": true, "delete": true},
      "cadastros": {"view": true, "create": true, "update": true, "delete": true},
      "usuarios": {"view": true, "create": true, "update": true, "delete": true},
      "configuracoes": {"view": true, "create": true, "update": true, "delete": true},
      "auditoria": {"view": true, "create": true, "update": true, "delete": true},
      "tutorial": {"view": true, "create": true, "update": true, "delete": true}
    },
    "gerente": {
      "dashboard": {"view": true},
      "financeiro": {"view": true, "create": true, "update": true, "delete": false},
      "secretaria": {"view": true, "create": true, "update": true, "delete": false},
      "ebd": {"view": true, "create": true, "update": true, "delete": false},
      "patrimonio": {"view": true, "create": true, "update": true, "delete": false},
      "cadastros": {"view": true, "create": true, "update": true, "delete": false},
      "configuracoes": {"view": false, "create": false, "update": false, "delete": false}
    },
    "secretario": {
      "dashboard": {"view": true},
      "financeiro": {"view": false, "create": false, "update": false, "delete": false},
      "secretaria": {"view": true, "create": true, "update": true, "delete": false},
      "ebd": {"view": true, "create": true, "update": true, "delete": false},
      "patrimonio": {"view": true, "create": true, "update": true, "delete": false},
      "portal": {"view": true, "create": true, "update": true, "delete": false},
      "cadastros": {"view": true, "create": true, "update": true, "delete": false},
      "configuracoes": {"view": false, "create": false, "update": false, "delete": false}
    },
    "tesoureiro": {
      "dashboard": {"view": true},
      "financeiro": {"view": true, "create": true, "update": true, "delete": false},
      "secretaria": {"view": false, "create": false, "update": false, "delete": false},
      "ebd": {"view": false, "create": false, "update": false, "delete": false},
      "patrimonio": {"view": false, "create": false, "update": false, "delete": false},
      "cadastros": {"view": true, "create": true, "update": true, "delete": false},
      "configuracoes": {"view": false, "create": false, "update": false, "delete": false}
    },
    "operador": {
      "dashboard": {"view": true},
      "financeiro": {"view": true, "create": true, "update": false, "delete": false},
      "secretaria": {"view": true, "create": true, "update": false, "delete": false},
      "ebd": {"view": true, "create": true, "update": false, "delete": false},
      "patrimonio": {"view": true, "create": true, "update": false, "delete": false},
      "configuracoes": {"view": false, "create": false, "update": false, "delete": false}
    },
    "consulta": {
      "dashboard": {"view": true},
      "financeiro": {"view": true, "create": false, "update": false, "delete": false},
      "secretaria": {"view": true, "create": false, "update": false, "delete": false},
      "ebd": {"view": true, "create": false, "update": false, "delete": false},
      "patrimonio": {"view": true, "create": false, "update": false, "delete": false},
      "configuracoes": {"view": false, "create": false, "update": false, "delete": false}
    },
    "membro": {
      "portal": {"view": true, "create": true, "update": true, "delete": false},
      "dashboard": {"view": false},
      "financeiro": {"view": false},
      "secretaria": {"view": false},
      "ebd": {"view": false},
      "patrimonio": {"view": false},
      "configuracoes": {"view": false}
    }
  },
  "dashboard": {
    "admin": {"financeiro_resumo": true, "saldo_caixa": true, "secretaria_membros": true, "secretaria_aniversariantes": true, "ebd_resumo": true, "patrimonio_resumo": true},
    "gerente": {"financeiro_resumo": true, "saldo_caixa": true, "secretaria_membros": false, "secretaria_aniversariantes": false, "ebd_resumo": false, "patrimonio_resumo": false},
    "secretario": {"financeiro_resumo": false, "saldo_caixa": false, "secretaria_membros": true, "secretaria_aniversariantes": true, "ebd_resumo": true, "patrimonio_resumo": true},
    "tesoureiro": {"financeiro_resumo": true, "saldo_caixa": true, "secretaria_membros": false, "secretaria_aniversariantes": false, "ebd_resumo": false, "patrimonio_resumo": false},
    "operador": {"financeiro_resumo": false, "saldo_caixa": false, "secretaria_membros": true, "secretaria_aniversariantes": true, "ebd_resumo": false, "patrimonio_resumo": false},
    "consulta": {"financeiro_resumo": false, "saldo_caixa": false, "secretaria_membros": false, "secretaria_aniversariantes": false, "ebd_resumo": true, "patrimonio_resumo": false},
    "membro": {"financeiro_resumo": false, "saldo_caixa": false, "secretaria_membros": false, "secretaria_aniversariantes": false, "ebd_resumo": false, "patrimonio_resumo": false}
  },
  "pagamentos": {
    "admin": {"Dinheiro": true, "Pix": true, "Cartão": true, "Transferência": true, "Cheque": true},
    "gerente": {"Dinheiro": true, "Pix": true, "Cartão": true, "Transferência": true, "Cheque": true},
    "secretario": {"Dinheiro": false, "Pix": false, "Cartão": false, "Transferência": false, "Cheque": false},
    "tesoureiro": {"Dinheiro": true, "Pix": true, "Cartão": true, "Transferência": true, "Cheque": true},
    "operador": {"Dinheiro": false, "Pix": false, "Cartão": false, "Transferência": false, "Cheque": false},
    "consulta": {"Dinheiro": false, "Pix": false, "Cartão": false, "Transferência": false, "Cheque": false},
    "membro": {"Dinheiro": false, "Pix": false, "Cartão": false, "Transferência": false, "Cheque": false}
  },
  "financeiro": {
    "admin": {"ver_operacoes_dinheiro": true, "ver_valores_registros_dinheiro": true, "ver_totais_dinheiro": true, "ver_operacoes_pix": true, "ver_valores_registros_pix": true, "ver_totais_pix": true, "ver_operacoes_cartao": true, "ver_valores_registros_cartao": true, "ver_totais_cartao": true, "ver_operacoes_transferencia": true, "ver_valores_registros_transferencia": true, "ver_totais_transferencia": true, "ver_operacoes_cheque": true, "ver_valores_registros_cheque": true, "ver_totais_cheque": true},
    "gerente": {"ver_operacoes_dinheiro": true, "ver_valores_registros_dinheiro": true, "ver_totais_dinheiro": true, "ver_operacoes_pix": true, "ver_valores_registros_pix": true, "ver_totais_pix": true, "ver_operacoes_cartao": true, "ver_valores_registros_cartao": true, "ver_totais_cartao": true, "ver_operacoes_transferencia": true, "ver_valores_registros_transferencia": true, "ver_totais_transferencia": true, "ver_operacoes_cheque": true, "ver_valores_registros_cheque": true, "ver_totais_cheque": true},
    "secretario": {"ver_operacoes_dinheiro": false, "ver_valores_registros_dinheiro": false, "ver_totais_dinheiro": false, "ver_operacoes_pix": false, "ver_valores_registros_pix": false, "ver_totais_pix": false, "ver_operacoes_cartao": false, "ver_valores_registros_cartao": false, "ver_totais_cartao": false, "ver_operacoes_transferencia": false, "ver_valores_registros_transferencia": false, "ver_totais_transferencia": false, "ver_operacoes_cheque": false, "ver_valores_registros_cheque": false, "ver_totais_cheque": false},
    "tesoureiro": {"ver_operacoes_dinheiro": true, "ver_valores_registros_dinheiro": true, "ver_totais_dinheiro": true, "ver_operacoes_pix": true, "ver_valores_registros_pix": true, "ver_totais_pix": true, "ver_operacoes_cartao": true, "ver_valores_registros_cartao": true, "ver_totais_cartao": true, "ver_operacoes_transferencia": true, "ver_valores_registros_transferencia": true, "ver_totais_transferencia": true, "ver_operacoes_cheque": true, "ver_valores_registros_cheque": true, "ver_totais_cheque": true},
    "operador": {"ver_operacoes_dinheiro": false, "ver_valores_registros_dinheiro": false, "ver_totais_dinheiro": false, "ver_operacoes_pix": false, "ver_valores_registros_pix": false, "ver_totais_pix": false, "ver_operacoes_cartao": false, "ver_valores_registros_cartao": false, "ver_totais_cartao": false, "ver_operacoes_transferencia": false, "ver_valores_registros_transferencia": false, "ver_totais_transferencia": false, "ver_operacoes_cheque": false, "ver_valores_registros_cheque": false, "ver_totais_cheque": false},
    "consulta": {"ver_operacoes_dinheiro": false, "ver_valores_registros_dinheiro": false, "ver_totais_dinheiro": false, "ver_operacoes_pix": false, "ver_valores_registros_pix": false, "ver_totais_pix": false, "ver_operacoes_cartao": false, "ver_valores_registros_cartao": false, "ver_totais_cartao": false, "ver_operacoes_transferencia": false, "ver_valores_registros_transferencia": false, "ver_totais_transferencia": false, "ver_operacoes_cheque": false, "ver_valores_registros_cheque": false, "ver_totais_cheque": false},
    "membro": {"ver_operacoes_dinheiro": false, "ver_valores_registros_dinheiro": false, "ver_totais_dinheiro": false, "ver_operacoes_pix": false, "ver_valores_registros_pix": false, "ver_totais_pix": false, "ver_operacoes_cartao": false, "ver_valores_registros_cartao": false, "ver_totais_cartao": false, "ver_operacoes_transferencia": false, "ver_valores_registros_transferencia": false, "ver_totais_transferencia": false, "ver_operacoes_cheque": false, "ver_valores_registros_cheque": false, "ver_totais_cheque": false}
  }
}
$permissoes$::jsonb;
begin

insert into public.app_configuracoes (chave, valor, updated_at)
values ('permissoes_usuarios', v_defaults, now())
on conflict (chave) do update
  set valor = public.jsonb_apply_permission_defaults_v59(public.app_configuracoes.valor, excluded.valor),
      updated_at = now();

update public.app_configuracoes c
   set valor = public.jsonb_apply_permission_defaults_v59(c.valor, v_defaults),
       updated_at = now()
 where c.chave <> 'permissoes_usuarios'
   and c.chave like 'permissoes\_usuarios\_%' escape '\';
end;
$$;

drop function if exists public.jsonb_apply_permission_defaults_v59(jsonb,jsonb);

notify pgrst, 'reload schema';
commit;
