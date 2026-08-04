const monthIndex = (value) => {
  if (!value) return null;
  const text = String(value).slice(0, 7);
  const match = text.match(/^(\d{4})-(\d{2})$/);
  if (!match) return null;
  return Number(match[1]) * 12 + Number(match[2]) - 1;
};

export function calcularDepreciacaoPatrimonio(bem, categoria, competencia) {
  const valorAquisicao = Math.max(0, Number(bem?.valor_aquisicao) || 0);
  const depreciavel = bem?.depreciavel ?? categoria?.depreciavel ?? false;
  const vidaUtilMeses = Number(bem?.vida_util_meses || categoria?.vida_util_meses || 0);
  const residualCategoria = valorAquisicao * Math.max(0, Math.min(100, Number(categoria?.valor_residual_percentual) || 0)) / 100;
  const valorResidual = Math.max(0, Math.min(valorAquisicao, Number(bem?.valor_residual) || residualCategoria));
  const inicio = bem?.depreciacao_inicio || bem?.data_aquisicao;
  const inicioMes = monthIndex(inicio);
  const competenciaMes = monthIndex(competencia);
  const base = Math.max(0, valorAquisicao - valorResidual);

  if (!depreciavel || !vidaUtilMeses || inicioMes === null || competenciaMes === null || competenciaMes < inicioMes || base <= 0) {
    return {
      elegivel: false,
      valorMensal: 0,
      depreciacaoAcumulada: 0,
      valorContabil: valorAquisicao,
      vidaUtilMeses,
      valorResidual,
      mesesDepreciados: 0,
    };
  }

  const mesesDepreciados = Math.min(vidaUtilMeses, competenciaMes - inicioMes + 1);
  const valorMensal = base / vidaUtilMeses;
  const depreciacaoAcumulada = Math.min(base, valorMensal * mesesDepreciados);
  return {
    elegivel: true,
    valorMensal,
    depreciacaoAcumulada,
    valorContabil: Math.max(valorResidual, valorAquisicao - depreciacaoAcumulada),
    vidaUtilMeses,
    valorResidual,
    mesesDepreciados,
  };
}
