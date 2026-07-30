import { money } from '../value-objects/Money.js';
import { ensureReferencia } from '../value-objects/Referencia.js';
import { transferenciaImpacto } from './calcularTransferencias.js';

export function filtrarPorReferenciaECaixa(rows, { referencia, caixaIds = [] } = {}) {
  const ref = referencia ? ensureReferencia(referencia) : null;
  const caixas = new Set((caixaIds || []).filter(Boolean).map(String));
  return (rows || []).filter((row) => {
    const okRef = !ref || ensureReferencia(row.referencia || row.data) === ref;
    const caixa = row.tipo_caixa_id || row.caixa_id;
    const okCaixa = caixas.size === 0 || caixas.has(String(caixa || ''));
    return okRef && okCaixa;
  });
}

export function filtrarTransferenciasPorReferencia(rows, referencia) {
  const ref = referencia ? ensureReferencia(referencia) : null;
  return (rows || []).filter((row) => !ref || ensureReferencia(row.referencia || row.data) === ref);
}

export function calcularResumoFinanceiro({ receitas = [], despesas = [], transferencias = [], referencia, caixaIds = [] } = {}) {
  const receitasFiltradas = filtrarPorReferenciaECaixa(receitas, { referencia, caixaIds });
  const despesasFiltradas = filtrarPorReferenciaECaixa(despesas, { referencia, caixaIds });
  const transferenciasFiltradas = filtrarTransferenciasPorReferencia(transferencias, referencia);
  const totalReceitas = receitasFiltradas.reduce((sum, item) => sum + money(item.valor), 0);
  const totalDespesas = despesasFiltradas.reduce((sum, item) => sum + money(item.valor), 0);
  const transferenciasLiquidas = transferenciaImpacto(transferenciasFiltradas, caixaIds);

  return {
    entradas: totalReceitas,
    saidas: totalDespesas,
    transferenciasLiquidas,
    saldo: totalReceitas - totalDespesas + transferenciasLiquidas,
    qtdReceitas: receitasFiltradas.length,
    qtdDespesas: despesasFiltradas.length,
    qtdTransferencias: transferenciasFiltradas.length,
  };
}
