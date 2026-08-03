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

function onlyDigits(value: unknown) {
  return String(value || '').replace(/\D+/g, '');
}

function isValidCpf(value: unknown) {
  const cpf = onlyDigits(value);
  if (cpf.length !== 11 || /^(\d)\1{10}$/.test(cpf)) return false;
  let sum = 0;
  for (let i = 0; i < 9; i += 1) sum += Number(cpf[i]) * (10 - i);
  let digit = (sum * 10) % 11;
  if (digit === 10) digit = 0;
  if (digit !== Number(cpf[9])) return false;
  sum = 0;
  for (let i = 0; i < 10; i += 1) sum += Number(cpf[i]) * (11 - i);
  digit = (sum * 10) % 11;
  if (digit === 10) digit = 0;
  return digit === Number(cpf[10]);
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

    if (callerError || !callerProfile?.ativo) return json({ error: 'Usuário sem permissão para criar acesso do membro.' }, 403);
    const callerRole = String(callerProfile.role || '').toLowerCase();
    if (!['master', 'admin', 'secretario'].includes(callerRole)) return json({ error: 'Apenas Master, Admin ou Secretário podem criar acesso para membros.' }, 403);

    const body = await req.json().catch(() => ({}));
    const membroId = String(body.membro_id || '').trim();
    if (!membroId) return json({ error: 'Membro não informado.' }, 400);

    const { data: membro, error: membroError } = await admin
      .from('membros')
      .select('id,nome,email,cpf,empresa_id,situacao,ativo')
      .eq('id', membroId)
      .maybeSingle();

    if (membroError || !membro?.id) return json({ error: 'Membro não encontrado.' }, 404);
    if (callerRole !== 'master' && membro.empresa_id !== callerProfile.empresa_id) {
      return json({ error: 'Você só pode criar acesso para membros da sua igreja.' }, 403);
    }

    const email = String(membro.email || '').trim().toLowerCase();
    const cpf = onlyDigits(membro.cpf);
    if (!email) return json({ error: 'Informe um e-mail no cadastro do membro antes de criar o acesso.' }, 400);
    if (!isValidCpf(cpf)) return json({ error: 'Informe um CPF válido no cadastro do membro. A senha inicial usa o CPF sem pontuação.' }, 400);

    const { data: linkedProfile } = await admin
      .from('profiles')
      .select('id,email,membro_id,role')
      .eq('membro_id', membro.id)
      .maybeSingle();

    if (linkedProfile?.id) {
      return json({ error: 'Este membro já possui um perfil de acesso vinculado.' }, 409);
    }

    const { data: emailProfile } = await admin
      .from('profiles')
      .select('id,email,membro_id,role')
      .ilike('email', email)
      .maybeSingle();

    if (emailProfile?.id) {
      return json({ error: 'Já existe um usuário com este e-mail. Vincule pelo cadastro de usuários para evitar duplicidade.' }, 409);
    }

    const metadata = {
      nome: membro.nome || '',
      empresa_id: membro.empresa_id || '',
      membro_id: membro.id,
      perfil: 'membro',
      criado_por: caller.id,
    };

    const created = await admin.auth.admin.createUser({
      email,
      password: cpf,
      email_confirm: true,
      user_metadata: metadata,
    });

    if (created.error || !created.data?.user?.id) {
      const message = String(created.error?.message || '');
      const alreadyExists = /already|registered|exist|user/i.test(message);
      if (alreadyExists) {
        return json({ error: 'Este e-mail já existe no Auth. Vincule o membro manualmente em Usuários e Permissões.' }, 409);
      }
      throw created.error;
    }

    const profilePayload = {
      id: created.data.user.id,
      nome: membro.nome || '',
      email,
      role: 'membro',
      ativo: true,
      empresa_id: membro.empresa_id,
      membro_id: membro.id,
      must_change_password: true,
      convite_enviado_em: new Date().toISOString(),
      convite_enviado_por: caller.id,
      ultimo_convite_status: 'acesso_membro_senha_padrao_cpf',
    };

    const { error: profileError } = await admin.from('profiles').upsert(profilePayload, { onConflict: 'id' });
    if (profileError) throw profileError;

    return json({
      ok: true,
      email,
      role: 'membro',
      membro_id: membro.id,
      senha_inicial: 'CPF sem pontuação',
    });
  } catch (err) {
    return json({ error: err?.message || 'Não foi possível criar o acesso do membro.' }, 500);
  }
});
