import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.4';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Método não permitido.' }, 405);

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !serviceRoleKey) {
      return json({ error: 'Variáveis SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY não configuradas.' }, 500);
    }

    const authHeader = req.headers.get('Authorization') || '';
    const jwt = authHeader.replace('Bearer ', '').trim();
    if (!jwt) return json({ error: 'Sessão não informada.' }, 401);

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: userData, error: userError } = await admin.auth.getUser(jwt);
    const caller = userData?.user;
    if (userError || !caller?.id) return json({ error: 'Sessão inválida.' }, 401);

    const { data: callerProfile, error: callerError } = await admin
      .from('profiles')
      .select('id,email,role,ativo,empresa_id')
      .eq('id', caller.id)
      .maybeSingle();

    if (callerError || !callerProfile?.ativo) return json({ error: 'Usuário sem permissão para enviar convites.' }, 403);
    const callerRole = String(callerProfile.role || '').toLowerCase();
    if (!['master', 'admin'].includes(callerRole)) return json({ error: 'Apenas administradores podem enviar convites.' }, 403);

    const body = await req.json().catch(() => ({}));
    const profileId = String(body.profile_id || '').trim();
    const redirectTo = String(body.redirect_to || '').trim() || req.headers.get('Origin') || undefined;
    if (!profileId) return json({ error: 'Perfil do usuário não informado.' }, 400);

    const { data: target, error: targetError } = await admin
      .from('profiles')
      .select('id,nome,email,role,ativo,empresa_id')
      .eq('id', profileId)
      .maybeSingle();

    if (targetError || !target?.id) return json({ error: 'Usuário convidado não encontrado.' }, 404);
    if (!target.email) return json({ error: 'Usuário convidado sem e-mail.' }, 400);
    if (String(target.role || '').toLowerCase() === 'master') return json({ error: 'Convite Master não permitido por este fluxo.' }, 403);
    if (callerRole !== 'master' && target.empresa_id !== callerProfile.empresa_id) {
      return json({ error: 'Você só pode convidar usuários da sua igreja.' }, 403);
    }

    const email = String(target.email).trim().toLowerCase();
    const metadata = {
      nome: target.nome || '',
      empresa_id: target.empresa_id || '',
      profile_id: target.id,
      convidado_por: caller.id,
    };

    let action = 'invite_sent';
    const invite = await admin.auth.admin.inviteUserByEmail(email, {
      redirectTo,
      data: metadata,
    });

    if (invite.error) {
      const msg = String(invite.error.message || '').toLowerCase();
      const alreadyExists = msg.includes('already') || msg.includes('registered') || msg.includes('exist') || msg.includes('user');
      if (!alreadyExists) throw invite.error;

      const reset = await admin.auth.resetPasswordForEmail(email, { redirectTo });
      if (reset.error) throw reset.error;
      action = 'password_reset_sent';
    }

    const statusPatch = {
      convite_enviado_em: new Date().toISOString(),
      convite_enviado_por: caller.id,
      ultimo_convite_status: action,
    };
    // Não bloqueia o envio caso as colunas opcionais ainda não existam.
    await admin.from('profiles').update(statusPatch).eq('id', target.id);

    return json({ ok: true, action, email });
  } catch (err) {
    return json({ error: err?.message || 'Não foi possível enviar o convite.' }, 500);
  }
});
