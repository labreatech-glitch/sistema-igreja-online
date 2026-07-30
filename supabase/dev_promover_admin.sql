-- DEV ONLY: promove/libera um usuário para entrar no sistema.
-- Troque o e-mail abaixo pelo e-mail cadastrado no Supabase Auth.
-- Execute no SQL Editor do Supabase após criar o usuário pela tela de cadastro/login.

update public.profiles
set role = 'admin', ativo = true, updated_at = now()
where lower(email) = lower('seu-email@exemplo.com');

-- Conferência:
select id, nome, email, role, ativo from public.profiles order by created_at desc;
