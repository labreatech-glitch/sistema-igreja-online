export function normalizarNomePessoa(nome = '') {
  return String(nome || '').trim().replace(/\s+/g, ' ').toUpperCase();
}

export function validarMembroBasico(membro = {}) {
  const nome = normalizarNomePessoa(membro.nome);
  if (!nome) return { ok: false, error: 'Nome é obrigatório.' };
  return { ok: true, value: { ...membro, nome } };
}
