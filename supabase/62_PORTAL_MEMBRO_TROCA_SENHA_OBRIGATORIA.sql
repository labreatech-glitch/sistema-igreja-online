-- V62 — Troca obrigatória da senha temporária do Portal do Membro
-- Escopo:
--   1) Marca perfis que precisam trocar a senha no próximo login.
--   2) Expõe uma função segura para o próprio usuário concluir a troca após atualizar o Auth.

begin;

alter table public.profiles
  add column if not exists must_change_password boolean not null default false;

comment on column public.profiles.must_change_password is
  'Quando true, o frontend bloqueia o acesso e exige troca de senha antes de liberar o sistema.';

create or replace function public.confirm_password_changed()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles
  set
    must_change_password = false,
    ultimo_convite_status = case
      when ultimo_convite_status = 'acesso_membro_senha_padrao_cpf'
        then 'senha_alterada_primeiro_acesso'
      else ultimo_convite_status
    end
  where id = auth.uid()
    and must_change_password = true;
end;
$$;

grant execute on function public.confirm_password_changed() to authenticated;

notify pgrst, 'reload schema';
commit;
