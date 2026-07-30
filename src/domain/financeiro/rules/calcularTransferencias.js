export function transferenciaAtiva(row) {
  return Boolean(row) && String(row.status || 'concluida').toLowerCase() !== 'estornada';
}

export function transferenciaImpacto(rows = [], caixaIds = []) {
  const ids = new Set((Array.isArray(caixaIds) ? caixaIds : []).filter(Boolean).map(String));
  if (ids.size === 0) return 0;

  return (rows || []).filter(transferenciaAtiva).reduce((sum, row) => {
    const valor = Number(row?.valor) || 0;
    const origemIncluida = ids.has(String(row?.caixa_origem_id || ''));
    const destinoIncluido = ids.has(String(row?.caixa_destino_id || ''));
    return sum + (destinoIncluido ? valor : 0) - (origemIncluida ? valor : 0);
  }, 0);
}

export function transferenciaResumoPerimetro(rows = [], caixaIds = []) {
  const ids = new Set((Array.isArray(caixaIds) ? caixaIds : []).filter(Boolean).map(String));

  return (rows || []).filter(transferenciaAtiva).reduce(
    (resumo, row) => {
      const valor = Number(row?.valor) || 0;
      const origemIncluida = ids.size === 0 || ids.has(String(row?.caixa_origem_id || ''));
      const destinoIncluido = ids.size === 0 || ids.has(String(row?.caixa_destino_id || ''));

      if (origemIncluida && destinoIncluido) resumo.internas += valor;
      else if (origemIncluida) resumo.enviadas += valor;
      else if (destinoIncluido) resumo.recebidas += valor;

      if (origemIncluida || destinoIncluido) resumo.movimentadas += valor;
      resumo.liquido = resumo.recebidas - resumo.enviadas;
      return resumo;
    },
    { internas: 0, enviadas: 0, recebidas: 0, movimentadas: 0, liquido: 0 },
  );
}
