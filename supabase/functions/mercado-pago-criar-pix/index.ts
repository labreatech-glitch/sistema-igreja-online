import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Método não permitido.' }, 405);

  try {
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
    const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY');
    const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const MERCADO_PAGO_ACCESS_TOKEN = Deno.env.get('MERCADO_PAGO_ACCESS_TOKEN');
    const WEBHOOK_FUNCTION_NAME = Deno.env.get('MERCADO_PAGO_WEBHOOK_FUNCTION') || 'mercado-pago-webhook';

    if (!SUPABASE_URL || !ANON_KEY || !SERVICE_ROLE_KEY || !MERCADO_PAGO_ACCESS_TOKEN) {
      throw new Error('Secrets obrigatórios não configurados.');
    }

    const authHeader = req.headers.get('Authorization') || '';
    if (!authHeader.startsWith('Bearer ')) return json({ error: 'Autenticação obrigatória.' }, 401);

    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) return json({ error: 'Sessão inválida.' }, 401);

    const body = await req.json().catch(() => null);
    const planoId = body?.plano_id;
    const empresaId = body?.empresa_id;
    if (!planoId || !empresaId) return json({ error: 'Informe plano_id e empresa_id.' }, 400);

    const { data: profile, error: profileError } = await admin
      .from('profiles')
      .select('id,empresa_id,role,ativo')
      .eq('id', authData.user.id)
      .maybeSingle();
    if (profileError || !profile?.ativo) return json({ error: 'Usuário sem perfil ativo.' }, 403);

    const isMaster = profile.role === 'master';
    const isOwnCompanyAdmin = ['admin', 'gerente'].includes(profile.role) && profile.empresa_id === empresaId;
    if (!isMaster && !isOwnCompanyAdmin) return json({ error: 'Sem permissão para gerar cobrança desta empresa.' }, 403);

    const [{ data: plano, error: planoError }, { data: empresa, error: empresaError }] = await Promise.all([
      admin.from('assinaturas_planos').select('id,nome,valor,dias_acesso,ativo').eq('id', planoId).eq('ativo', true).single(),
      admin.from('empresas').select('id,nome,nome_fantasia,email,ativo').eq('id', empresaId).eq('ativo', true).single(),
    ]);
    if (planoError || !plano) return json({ error: 'Plano ativo não encontrado.' }, 404);
    if (empresaError || !empresa) return json({ error: 'Empresa ativa não encontrada.' }, 404);

    const valor = Number(plano.valor || 0);
    if (!Number.isFinite(valor) || valor <= 0) return json({ error: 'O plano precisa ter valor maior que zero.' }, 400);

    const expiraEm = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
    const { data: pagamento, error: insertError } = await admin
      .from('assinaturas_pagamentos')
      .insert({
        empresa_id: empresaId,
        plano_id: planoId,
        valor,
        status: 'Pendente',
        forma_pagamento: 'Pix',
        vencimento_em: expiraEm,
        criado_por: authData.user.id,
      })
      .select('id')
      .single();
    if (insertError || !pagamento) throw new Error(insertError?.message || 'Não foi possível registrar o pagamento.');

    const notificationUrl = `${SUPABASE_URL}/functions/v1/${WEBHOOK_FUNCTION_NAME}`;
    const payerName = empresa.nome_fantasia || empresa.nome || 'Cliente';
    const mpResponse = await fetch('https://api.mercadopago.com/v1/payments', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${MERCADO_PAGO_ACCESS_TOKEN}`,
        'Content-Type': 'application/json',
        'X-Idempotency-Key': pagamento.id,
      },
      body: JSON.stringify({
        transaction_amount: valor,
        description: `Assinatura ${plano.nome} — ${payerName}`,
        payment_method_id: 'pix',
        payer: {
          email: empresa.email || authData.user.email || 'cliente@exemplo.com',
          first_name: payerName,
        },
        external_reference: pagamento.id,
        notification_url: notificationUrl,
        date_of_expiration: expiraEm,
      }),
    });
    const mp = await mpResponse.json();

    if (!mpResponse.ok) {
      await admin.from('assinaturas_pagamentos').update({
        status: 'Falhou',
        mercado_pago_status: mp?.status || 'rejected',
        mercado_pago_status_detail: mp?.status_detail || null,
        retorno: mp,
      }).eq('id', pagamento.id);
      return json({ error: mp?.message || 'Mercado Pago recusou a criação do Pix.', detalhe: mp }, 400);
    }

    const transaction = mp?.point_of_interaction?.transaction_data || {};
    const update = {
      mercado_pago_payment_id: String(mp.id || ''),
      mercado_pago_status: mp.status || 'pending',
      mercado_pago_status_detail: mp.status_detail || null,
      status: mp.status === 'approved' ? 'Pago' : 'Aguardando Pix',
      qr_code: transaction.qr_code || null,
      qr_code_base64: transaction.qr_code_base64 || null,
      pix_copia_cola: transaction.qr_code || null,
      ticket_url: transaction.ticket_url || null,
      retorno: mp,
    };
    const { error: updateError } = await admin.from('assinaturas_pagamentos').update(update).eq('id', pagamento.id);
    if (updateError) throw new Error(updateError.message);

    return json({
      pagamento_id: pagamento.id,
      mercado_pago_payment_id: mp.id,
      valor,
      status: update.status,
      qr_code: update.qr_code,
      qr_code_base64: update.qr_code_base64,
      pix_copia_cola: update.pix_copia_cola,
      ticket_url: update.ticket_url,
      vencimento_em: expiraEm,
    });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : String(error) }, 400);
  }
});
