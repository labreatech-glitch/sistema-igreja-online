const number = (value) => Number.isFinite(Number(value)) ? Number(value) : 0;
export function referenciaParts(referencia) {
  const match = String(referencia || '').match(/^(\d{4})-(\d{2})$/);
  if (!match) return null;
  return { ano: Number(match[1]), mes: Number(match[2]) };
}
export function referenciaAdd(referencia, delta) {
  const parts = referenciaParts(referencia);
  if (!parts) return referencia;
  const date = new Date(Date.UTC(parts.ano, parts.mes - 1 + delta, 1));
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}`;
}
export function categoriaOcorreNaReferencia(categoria, referencia) {
  if (!categoria?.recorrente_padrao) return !!categoria?.incluir_previsao_padrao;
  const parts = referenciaParts(referencia);
  if (!parts) return false;
  const periodicidade = categoria.periodicidade_padrao || 'mensal';
  const inicio = referenciaParts(String(categoria.previsao_inicio_referencia || referencia));
  if (periodicidade === 'anual') return parts.mes === number(categoria.mes_vencimento_padrao || inicio?.mes || 1);
  const intervalo = periodicidade === 'trimestral' ? 3 : periodicidade === 'semestral' ? 6 : 1;
  if (!inicio) return true;
  const diff = (parts.ano - inicio.ano) * 12 + parts.mes - inicio.mes;
  return diff >= 0 && diff % intervalo === 0;
}
export function mediaHistoricaCategoria(despesas, categoriaId, referencia, meses = 6) {
  const refs = new Set(Array.from({ length: Math.max(1, meses) }, (_, index) => referenciaAdd(referencia, -(index + 1))));
  const porMes = new Map([...refs].map((ref) => [ref, 0]));
  (despesas || []).forEach((row) => {
    if (row.categoria_id === categoriaId && porMes.has(row.referencia)) porMes.set(row.referencia, porMes.get(row.referencia) + number(row.valor));
  });
  return [...porMes.values()].reduce((sum, value) => sum + value, 0) / porMes.size;
}
export function calcularValorPrevistoCategoria(categoria, despesas, referencia, mesesHistorico = 6) {
  const base = categoria.valor_previsto_padrao == null ? null : number(categoria.valor_previsto_padrao);
  const media = mediaHistoricaCategoria(despesas, categoria.id, referencia, mesesHistorico);
  switch (categoria.classificacao_padrao) {
    case 'fixa': return base ?? media;
    case 'variavel': return base ?? media;
    case 'mista': {
      const fixa = number(categoria.parcela_fixa_prevista);
      return base ?? Math.max(fixa, media);
    }
    case 'eventual': return categoria.incluir_previsao_padrao ? (base ?? media) : 0;
    default: return base ?? media;
  }
}
export function construirPrevisaoDespesas({ categorias = [], despesas = [], referencia, mesesHistorico = 6 }) {
  return categorias.filter((categoria) => categoria.ativo !== false && categoria.incluir_previsao_padrao && categoriaOcorreNaReferencia(categoria, referencia)).map((categoria) => {
    const previsto = calcularValorPrevistoCategoria(categoria, despesas, referencia, mesesHistorico);
    const realizado = despesas.filter((row) => row.categoria_id === categoria.id && row.referencia === referencia).reduce((sum, row) => sum + number(row.valor), 0);
    return { categoria, previsto, realizado, variacao: realizado - previsto, saldo: previsto - realizado };
  });
}
export function totaisPrevisao(linhas = []) {
  return linhas.reduce((acc, linha) => ({ previsto: acc.previsto + number(linha.previsto), realizado: acc.realizado + number(linha.realizado), variacao: acc.variacao + number(linha.variacao) }), { previsto: 0, realizado: 0, variacao: 0 });
}
