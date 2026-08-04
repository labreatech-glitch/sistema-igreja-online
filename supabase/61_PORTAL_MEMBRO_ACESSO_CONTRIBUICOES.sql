-- V61 — Acesso automático ao Portal do Membro e relatório exclusivo de contribuições
-- Escopo:
--   1) Garante vínculo opcional profiles.membro_id.
--   2) Permite que perfil "membro" leia somente seus próprios lançamentos de receita.
--   3) Restringe a leitura da tabela membros para perfil "membro" ao próprio cadastro.

begin;

alter table public.profiles
  add column if not exists membro_id uuid references public.membros(id) on delete set null;

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check
  check (role in ('master','admin','gerente','operador','consulta','secretario','tesoureiro','membro'));

create index if not exists idx_profiles_membro_id
  on public.profiles(membro_id);

create index if not exists idx_lancamentos_financeiros_membro_portal
  on public.lancamentos_financeiros(empresa_id, membro_id, referencia, data);

drop policy if exists membros_select on public.membros;
create policy membros_select on public.membros
for select
using (
  public.is_master()
  or (
    public.is_ativo()
    and empresa_id = public.current_empresa_id()
    and coalesce(public.current_role(), '') <> 'membro'
  )
  or (
    public.is_ativo()
    and empresa_id = public.current_empresa_id()
    and id = (
      select p.membro_id
      from public.profiles p
      where p.id = auth.uid()
        and p.role = 'membro'
        and p.ativo = true
        and p.membro_id is not null
      limit 1
    )
  )
);

drop policy if exists lancamentos_financeiros_member_select_own on public.lancamentos_financeiros;
create policy lancamentos_financeiros_member_select_own
on public.lancamentos_financeiros
for select
using (
  public.is_ativo()
  and empresa_id = public.current_empresa_id()
  and membro_id = (
    select p.membro_id
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'membro'
      and p.ativo = true
      and p.membro_id is not null
    limit 1
  )
);

grant select on public.lancamentos_financeiros to authenticated;

notify pgrst, 'reload schema';
commit;
