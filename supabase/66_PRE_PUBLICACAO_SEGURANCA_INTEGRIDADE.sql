-- V66 - Seguranca e integridade para publicacao
-- Migracao aditiva e idempotente. Nao remove dados existentes.

begin;

-- Mantem o comportamento historico dos e-mails Master, mas exige que o
-- e-mail do perfil corresponda ao e-mail autenticado no JWT.
create or replace function public.is_master()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce((
    select p.ativo and (
      p.role = 'master'
      or (
        lower(p.email) in ('labreatech@gmail.com','labreatech@hotmail.com')
        and lower(p.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
      )
    )
    from public.profiles p
    where p.id = auth.uid()
  ), false);
$$;

-- Impede que um autocadastro pendente grave no perfil um e-mail diferente
-- daquele efetivamente autenticado. Politicas administrativas permanecem iguais.
drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self on public.profiles for insert
  with check (
    auth.uid() = id
    and ativo = false
    and role in ('secretario','admin','gerente','operador','consulta','tesoureiro','membro')
    and lower(trim(email)) = lower(trim(coalesce(auth.jwt() ->> 'email', '')))
  );

drop policy if exists profiles_update_self_pending on public.profiles;
create policy profiles_update_self_pending on public.profiles for update
  using (auth.uid() = id and ativo = false)
  with check (
    auth.uid() = id
    and ativo = false
    and role in ('secretario','admin','gerente','operador','consulta','tesoureiro','membro')
    and lower(trim(email)) = lower(trim(coalesce(auth.jwt() ->> 'email', '')))
  );

-- Processa uma aprovacao PIX em uma unica transacao. O bloqueio da linha do
-- pagamento evita que webhooks simultaneos renovem a assinatura duas vezes.
create or replace function public.mercado_pago_processar_pagamento_aprovado(
  p_pagamento_id uuid,
  p_mercado_pago_payment_id text,
  p_mercado_pago_status text,
  p_mercado_pago_payload jsonb,
  p_processado_em timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_pagamento public.assinaturas_pagamentos%rowtype;
  v_assinatura public.assinaturas%rowtype;
  v_agora timestamptz := coalesce(p_processado_em, now());
  v_dias_acesso integer;
  v_assinatura_ativa boolean := false;
  v_vencimento_anterior timestamptz;
  v_base_renovacao timestamptz;
  v_vencimento_em timestamptz;
  v_regra_renovacao text;
begin
  if lower(coalesce(p_mercado_pago_status, '')) <> 'approved' then
    raise exception 'Somente pagamentos aprovados podem ser processados por esta funcao.';
  end if;

  select *
    into v_pagamento
    from public.assinaturas_pagamentos
   where id = p_pagamento_id
   for update;

  if not found then
    raise exception 'Pagamento nao localizado no sistema.';
  end if;

  if v_pagamento.status = 'Pago'
     and v_pagamento.pago_em is not null
     and v_pagamento.assinatura_id is not null then
    return jsonb_build_object(
      'already_processed', true,
      'status', v_pagamento.status,
      'pagamento_id', v_pagamento.id,
      'assinatura_id', v_pagamento.assinatura_id,
      'vencimento_em', v_pagamento.retorno #>> '{processamento_webhook,vencimento_em}',
      'base_renovacao', v_pagamento.retorno #>> '{processamento_webhook,base_renovacao}',
      'regra_renovacao', v_pagamento.retorno #>> '{processamento_webhook,regra_renovacao}'
    );
  end if;

  select coalesce((
    select dias_acesso
      from public.assinaturas_planos
     where id = v_pagamento.plano_id
  ), 30)
    into v_dias_acesso;

  select *
    into v_assinatura
    from public.assinaturas
   where empresa_id = v_pagamento.empresa_id
   order by created_at desc
   limit 1
   for update;

  if found then
    v_vencimento_anterior := v_assinatura.vencimento_em;
    v_assinatura_ativa := v_vencimento_anterior is not null and v_vencimento_anterior > v_agora;
  end if;

  v_base_renovacao := case
    when v_assinatura_ativa then v_vencimento_anterior
    else v_agora
  end;
  v_vencimento_em := v_base_renovacao + make_interval(days => v_dias_acesso);
  v_regra_renovacao := case
    when v_assinatura_ativa then 'Assinatura ativa: renovacao somada ao vencimento atual.'
    else 'Assinatura vencida ou inexistente: renovacao somada a partir de agora.'
  end;

  if v_assinatura.id is not null then
    update public.assinaturas
       set plano_id = v_pagamento.plano_id,
           status = 'Ativa',
           vencimento_em = v_vencimento_em,
           ultimo_pagamento_id = v_pagamento.id,
           updated_at = v_agora
     where id = v_assinatura.id
     returning * into v_assinatura;
  else
    insert into public.assinaturas (
      empresa_id,
      plano_id,
      status,
      inicio_em,
      vencimento_em,
      ultimo_pagamento_id,
      updated_at
    ) values (
      v_pagamento.empresa_id,
      v_pagamento.plano_id,
      'Ativa',
      v_agora,
      v_vencimento_em,
      v_pagamento.id,
      v_agora
    )
    returning * into v_assinatura;
  end if;

  update public.assinaturas_pagamentos
     set status = 'Pago',
         mercado_pago_status = p_mercado_pago_status,
         mercado_pago_payment_id = coalesce(nullif(p_mercado_pago_payment_id, ''), mercado_pago_payment_id),
         pago_em = coalesce(pago_em, v_agora),
         assinatura_id = v_assinatura.id,
         retorno = jsonb_build_object(
           'mercado_pago', coalesce(p_mercado_pago_payload, '{}'::jsonb),
           'processamento_webhook', jsonb_build_object(
             'payment_id', p_mercado_pago_payment_id,
             'status_mercado_pago', p_mercado_pago_status,
             'status_sistema', 'Pago',
             'processado_em', v_agora,
             'dias_acesso', v_dias_acesso,
             'assinatura_estava_ativa', v_assinatura_ativa,
             'vencimento_anterior', v_vencimento_anterior,
             'base_renovacao', v_base_renovacao,
             'regra_renovacao', v_regra_renovacao,
             'vencimento_em', v_vencimento_em
           )
         ),
         updated_at = v_agora
   where id = v_pagamento.id;

  return jsonb_build_object(
    'already_processed', false,
    'status', 'Pago',
    'pagamento_id', v_pagamento.id,
    'assinatura_id', v_assinatura.id,
    'vencimento_em', v_vencimento_em,
    'base_renovacao', v_base_renovacao,
    'regra_renovacao', v_regra_renovacao
  );
end;
$$;

revoke all on function public.mercado_pago_processar_pagamento_aprovado(uuid,text,text,jsonb,timestamptz) from public, anon, authenticated;
grant execute on function public.mercado_pago_processar_pagamento_aprovado(uuid,text,text,jsonb,timestamptz) to service_role;

notify pgrst, 'reload schema';
commit;
