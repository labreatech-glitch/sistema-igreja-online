import { transferenciaAtiva, transferenciaImpacto } from './calcularTransferencias.js';

function somar(rows = []) {
  return (rows || []).reduce((total, row) => total + (Number(row?.valor) || 0), 0);
}

function somarTransferencias(rows = [], field, caixaId) {
  return (rows || [])
    .filter(transferenciaAtiva)
    .filter((row) => String(row?.[field] || '') === String(caixaId || ''))
    .reduce((total, row) => total + Math.abs(Number(row?.valor) || 0), 0);
}

export function calcularPosicaoCaixaPrestacao({
  caixaId,
  receitasAnteriores = [],
  despesasAnteriores = [],
  transferenciasAnteriores = [],
  receitasPeriodo = [],
  despesasPeriodo = [],
  transferenciasPeriodo = [],
} = {}) {
  const receitas = somar(receitasPeriodo);
  const despesas = somar(despesasPeriodo);
  const transferenciasRecebidas = somarTransferencias(transferenciasPeriodo, 'caixa_destino_id', caixaId);
  const transferenciasEnviadas = somarTransferencias(transferenciasPeriodo, 'caixa_origem_id', caixaId);
  const saldoAnterior = somar(receitasAnteriores) - somar(despesasAnteriores) + transferenciaImpacto(transferenciasAnteriores, [caixaId]);
  const entradas = receitas + transferenciasRecebidas;
  const saidas = despesas + transferenciasEnviadas;
  const saldoPeriodo = entradas - saidas;

  return {
    saldoAnterior,
    receitas,
    despesas,
    transferenciasRecebidas,
    transferenciasEnviadas,
    entradas,
    saidas,
    saldoPeriodo,
    saldoAtual: saldoAnterior + saldoPeriodo,
  };
}
