import { classificarMovimentoBancario, identificarPessoaPix } from '../../domain/financeiro/rules/classificarMovimentoBancario.js';
import { ensureReferencia } from '../../domain/financeiro/value-objects/Referencia.js';
import { money } from '../../domain/financeiro/value-objects/Money.js';

export function prepararMovimentosOfx({ movimentos = [], referenciaPadrao, banco, caixaId }) {
  return movimentos.map((m) => {
    const valor = money(m.valor);
    const classificacao = classificarMovimentoBancario(m.historico, valor);
    const pessoa = identificarPessoaPix(m.historico);
    return {
      ...m,
      banco,
      caixaId,
      referencia: ensureReferencia(m.referencia || referenciaPadrao || m.data, m.data),
      valor,
      tipo: classificacao.tipo,
      categoria: m.categoria || classificacao.categoria,
      nomeIdentificado: pessoa.nome,
      documentoIdentificado: pessoa.documento,
      horaIdentificada: pessoa.hora,
      selecionado: m.selecionado !== false,
    };
  });
}

export async function importarMovimentosConfirmados({ financeiroRepository, movimentos = [] }) {
  if (!financeiroRepository) throw new Error('financeiroRepository é obrigatório.');
  const selecionados = movimentos.filter(m => m.selecionado !== false);
  return financeiroRepository.importarMovimentos(selecionados);
}
