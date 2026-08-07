-- 76_HABILITAR_CONTABILIDADE_PERMISSOES.sql
-- Compatibilidade para empresas com configurações de permissões anteriores ao módulo Contabilidade.
-- Preserva decisões explícitas existentes: só adiciona o módulo quando a chave ainda não existe.
begin;

update public.app_configuracoes
set valor = jsonb_set(
  jsonb_set(
    coalesce(valor::jsonb, '{}'::jsonb),
    '{menus,gerente,contabilidade}',
    '{"view":true,"create":false,"update":false,"delete":false}'::jsonb,
    true
  ),
  '{menus,tesoureiro,contabilidade}',
  '{"view":true,"create":true,"update":true,"delete":false}'::jsonb,
  true
)
where (chave = 'permissoes_usuarios' or chave like 'permissoes_usuarios_%')
  and not (coalesce(valor::jsonb, '{}'::jsonb) #> '{menus,gerente}' ? 'contabilidade')
  and not (coalesce(valor::jsonb, '{}'::jsonb) #> '{menus,tesoureiro}' ? 'contabilidade');

-- Casos em que apenas um dos dois perfis ainda não possuía a chave.
update public.app_configuracoes
set valor = jsonb_set(coalesce(valor::jsonb, '{}'::jsonb), '{menus,gerente,contabilidade}', '{"view":true,"create":false,"update":false,"delete":false}'::jsonb, true)
where (chave = 'permissoes_usuarios' or chave like 'permissoes_usuarios_%')
  and not (coalesce(valor::jsonb, '{}'::jsonb) #> '{menus,gerente}' ? 'contabilidade');

update public.app_configuracoes
set valor = jsonb_set(coalesce(valor::jsonb, '{}'::jsonb), '{menus,tesoureiro,contabilidade}', '{"view":true,"create":true,"update":true,"delete":false}'::jsonb, true)
where (chave = 'permissoes_usuarios' or chave like 'permissoes_usuarios_%')
  and not (coalesce(valor::jsonb, '{}'::jsonb) #> '{menus,tesoureiro}' ? 'contabilidade');

commit;
