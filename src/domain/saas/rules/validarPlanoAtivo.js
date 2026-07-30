export function assinaturaAtiva(assinatura = {}, now = new Date()) {
  if (!assinatura) return false;
  const status = String(assinatura.status || '').toLowerCase();
  if (status === 'ativa' || status === 'ativo') return true;
  if (status === 'teste') {
    const venc = assinatura.vencimento_em ? new Date(assinatura.vencimento_em) : null;
    return venc ? venc >= now : true;
  }
  return false;
}
