import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
};

function getPaymentIdFromPayload(payload: any, url: URL) {
  const fromBody =
    payload?.data?.id ||
    payload?.id ||
    payload?.payment_id ||
    payload?.resource;

  const fromUrl =
    url.searchParams.get('id') ||
    url.searchParams.get('data.id') ||
    url.searchParams.get('payment_id');

  const raw = fromBody || fromUrl;

  if (!raw) return null;

  const text = String(raw);
  const match = text.match(/payments\/(\d+)/);

  return match ? match[1] : text;
}

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  });
}


function parseSignatureHeader(xSignature: string) {
  const values = new Map<string, string>();

  for (const part of xSignature.split(',')) {
    const [key, ...rest] = part.trim().split('=');
    if (key && rest.length) values.set(key, rest.join('='));
  }

  return {
    ts: values.get('ts') || '',
    v1: values.get('v1') || '',
  };
}

function toHex(buffer: ArrayBuffer) {
  return Array.from(new Uint8Array(buffer))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

function constantTimeEqual(left: string, right: string) {
  if (left.length !== right.length) return false;

  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }

  return difference === 0;
}

async function validateMercadoPagoSignature({
  secret,
  xSignature,
  xRequestId,
  dataId,
}: {
  secret: string;
  xSignature: string;
  xRequestId: string;
  dataId: string;
}) {
  const { ts, v1 } = parseSignatureHeader(xSignature);
  if (!ts || !v1) return false;

  const manifestParts: string[] = [];
  if (dataId) manifestParts.push(`id:${dataId};`);
  if (xRequestId) manifestParts.push(`request-id:${xRequestId};`);
  manifestParts.push(`ts:${ts};`);

  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const signature = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(manifestParts.join('')),
  );

  return constantTimeEqual(toHex(signature), v1.toLowerCase());
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
    const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const MERCADO_PAGO_ACCESS_TOKEN = Deno.env.get('MERCADO_PAGO_ACCESS_TOKEN');
    const MERCADO_PAGO_WEBHOOK_SECRET = Deno.env.get('MERCADO_PAGO_WEBHOOK_SECRET');

    if (!SUPABASE_URL) {
      throw new Error('SUPABASE_URL não encontrada.');
    }

    if (!SERVICE_ROLE_KEY) {
      throw new Error('SUPABASE_SERVICE_ROLE_KEY não encontrada.');
    }

    if (!MERCADO_PAGO_ACCESS_TOKEN) {
      throw new Error('MERCADO_PAGO_ACCESS_TOKEN não encontrado nos Secrets do Supabase.');
    }

    if (!MERCADO_PAGO_WEBHOOK_SECRET) {
      throw new Error('MERCADO_PAGO_WEBHOOK_SECRET não encontrado nos Secrets do Supabase.');
    }

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: {
        persistSession: false,
      },
    });

    const url = new URL(req.url);

    let payload: any = {};
    try {
      payload = await req.json();
    } catch (_) {
      payload = {};
    }

    const paymentId = getPaymentIdFromPayload(payload, url);

    const xSignature = req.headers.get('x-signature') || '';
    const xRequestId = req.headers.get('x-request-id') || '';
    const signedDataId =
      url.searchParams.get('data.id') ||
      url.searchParams.get('id') ||
      String(payload?.data?.id || '');

    if (!xSignature || !xRequestId) {
      return jsonResponse({ ok: false, error: 'Notificação sem assinatura do Mercado Pago.' }, 401);
    }

    const validSignature = await validateMercadoPagoSignature({
      secret: MERCADO_PAGO_WEBHOOK_SECRET,
      xSignature,
      xRequestId,
      dataId: signedDataId,
    });

    if (!validSignature) {
      return jsonResponse({ ok: false, error: 'Assinatura do webhook inválida.' }, 401);
    }

    if (!paymentId) {
      return jsonResponse({
        ok: true,
        ignored: 'Notificação ignorada: nenhum payment id informado.',
        payload,
      });
    }

    // O simulador oficial envia um ID fictício (por exemplo, 123456) e
    // live_mode=false. A assinatura já foi validada acima; portanto,
    // confirmamos o recebimento com HTTP 200 sem consultar a API real.
    if (payload?.live_mode === false) {
      return jsonResponse({
        ok: true,
        simulated: true,
        ignored: 'Notificação simulada validada com sucesso.',
        mercado_pago_payment_id: paymentId,
      });
    }

    const mpResp = await fetch(`https://api.mercadopago.com/v1/payments/${paymentId}`, {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${MERCADO_PAGO_ACCESS_TOKEN}`,
        'Content-Type': 'application/json',
      },
    });

    const mp = await mpResp.json();

    if (!mpResp.ok) {
      throw new Error(mp?.message || 'Falha ao consultar pagamento no Mercado Pago.');
    }

    const externalReference = mp?.external_reference;

    if (!externalReference) {
      return jsonResponse({
        ok: true,
        ignored: 'Pagamento sem external_reference.',
        mercado_pago_payment_id: paymentId,
        mercado_pago_status: mp?.status,
      });
    }

    const { data: pagamento, error: pagamentoError } = await supabase
      .from('assinaturas_pagamentos')
      .select('*, assinaturas_planos(*)')
      .eq('id', externalReference)
      .maybeSingle();

    if (pagamentoError) {
      throw new Error(pagamentoError.message);
    }

    if (!pagamento) {
      return jsonResponse({
        ok: true,
        ignored: 'Pagamento não localizado no sistema.',
        external_reference: externalReference,
        mercado_pago_payment_id: paymentId,
      });
    }

    const aprovado = mp.status === 'approved';

    if (aprovado) {
      const processadoEm = new Date().toISOString();
      const { data: processamento, error: processamentoError } = await supabase.rpc(
        'mercado_pago_processar_pagamento_aprovado',
        {
          p_pagamento_id: pagamento.id,
          p_mercado_pago_payment_id: String(mp.id || paymentId),
          p_mercado_pago_status: mp.status,
          p_mercado_pago_payload: mp,
          p_processado_em: processadoEm,
        },
      );

      if (processamentoError) throw new Error(processamentoError.message);

      return jsonResponse({
        ok: true,
        mercado_pago_payment_id: paymentId,
        mercado_pago_status: mp.status,
        ...(processamento || {}),
      });
    }

    let statusSistema = 'Processando';

    if (mp.status === 'pending') statusSistema = 'Aguardando Pix';
    else if (mp.status === 'in_process') statusSistema = 'Processando';
    else if (mp.status === 'rejected') statusSistema = 'Recusado';
    else if (mp.status === 'cancelled') statusSistema = 'Cancelado';
    else statusSistema = mp.status || 'Processando';

    const agora = new Date();

    const pagamentoUpdate: Record<string, unknown> = {
      status: statusSistema,
      mercado_pago_status: mp.status || null,
      mercado_pago_payment_id: String(mp.id || paymentId),
      retorno: {
        mercado_pago: mp,
        processamento_webhook: {
          payment_id: String(mp.id || paymentId),
          status_mercado_pago: mp.status || null,
          status_sistema: statusSistema,
          processado_em: agora.toISOString(),
          dias_acesso: null,
          assinatura_estava_ativa: false,
          vencimento_anterior: null,
          base_renovacao: null,
          regra_renovacao: null,
          vencimento_em: null,
        },
      },
      updated_at: agora.toISOString(),
    };

    const { error: updatePagamentoError } = await supabase
      .from('assinaturas_pagamentos')
      .update(pagamentoUpdate)
      .eq('id', pagamento.id);

    if (updatePagamentoError) {
      throw new Error(updatePagamentoError.message);
    }

    return jsonResponse({
      ok: true,
      mercado_pago_payment_id: paymentId,
      mercado_pago_status: mp.status,
      status: statusSistema,
      pagamento_id: pagamento.id,
      assinatura_id: pagamento.assinatura_id || null,
      vencimento_em: null,
      base_renovacao: null,
      regra_renovacao: null,
    });
  } catch (e) {
    return jsonResponse(
      {
        ok: false,
        error: e instanceof Error ? e.message : String(e),
      },
      400,
    );
  }
});
