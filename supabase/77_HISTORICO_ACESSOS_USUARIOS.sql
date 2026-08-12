-- =========================================================
-- V77 - Histórico específico de acessos dos usuários
-- Migração aditiva e idempotente. Não altera acessos existentes.
-- =========================================================

begin;

alter table public.profiles
  add column if not exists ultimo_acesso_em timestamptz;

create table if not exists public.usuarios_acessos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid references public.empresas(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,
  usuario_nome text not null default '',
  usuario_email text not null default '',
  perfil text not null default '',
  auth_session_id text not null,
  origem text not null default 'web',
  plataforma text,
  user_agent text,
  acessado_em timestamptz not null default now(),
  constraint usuarios_acessos_user_session_unique unique (user_id, auth_session_id)
);

create index if not exists idx_usuarios_acessos_empresa_data
  on public.usuarios_acessos (empresa_id, acessado_em desc);
create index if not exists idx_usuarios_acessos_usuario_data
  on public.usuarios_acessos (user_id, acessado_em desc);

alter table public.usuarios_acessos enable row level security;

drop policy if exists usuarios_acessos_select on public.usuarios_acessos;
create policy usuarios_acessos_select on public.usuarios_acessos
for select using (
  public.is_master()
  or (
    public.is_admin()
    and empresa_id = public.current_empresa_id()
  )
);

-- Não há INSERT/UPDATE/DELETE direto pelo cliente. O registro passa pela
-- função abaixo, que obtém usuário, empresa e perfil da sessão autenticada.
create or replace function public.registrar_acesso_usuario(
  p_plataforma text default null,
  p_user_agent text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_profile public.profiles%rowtype;
  v_session_id text;
  v_acesso_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Sessão autenticada não encontrada.';
  end if;

  select *
    into v_profile
    from public.profiles
   where id = auth.uid();

  if not found or not coalesce(v_profile.ativo, false) then
    raise exception 'Perfil ativo não encontrado para registrar o acesso.';
  end if;

  v_session_id := nullif(auth.jwt() ->> 'session_id', '');
  if v_session_id is null then
    v_session_id := auth.uid()::text || ':' || coalesce(auth.jwt() ->> 'iat', extract(epoch from now())::bigint::text);
  end if;

  insert into public.usuarios_acessos (
    empresa_id,
    user_id,
    usuario_nome,
    usuario_email,
    perfil,
    auth_session_id,
    plataforma,
    user_agent
  ) values (
    v_profile.empresa_id,
    auth.uid(),
    coalesce(v_profile.nome, ''),
    coalesce(v_profile.email, ''),
    coalesce(v_profile.role, ''),
    v_session_id,
    nullif(left(coalesce(p_plataforma, ''), 120), ''),
    nullif(left(coalesce(p_user_agent, ''), 500), '')
  )
  on conflict (user_id, auth_session_id) do nothing
  returning id into v_acesso_id;

  if v_acesso_id is null then
    select id
      into v_acesso_id
      from public.usuarios_acessos
     where user_id = auth.uid()
       and auth_session_id = v_session_id;
  else
    update public.profiles
       set ultimo_acesso_em = now()
     where id = auth.uid();
  end if;

  return v_acesso_id;
end;
$$;

revoke all on function public.registrar_acesso_usuario(text,text) from public, anon;
grant execute on function public.registrar_acesso_usuario(text,text) to authenticated;
grant select on public.usuarios_acessos to authenticated;

notify pgrst, 'reload schema';
commit;
