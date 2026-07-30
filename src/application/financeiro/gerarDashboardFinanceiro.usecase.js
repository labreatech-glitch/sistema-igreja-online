import { calcularResumoFinanceiro } from '../../domain/financeiro/rules/calcularSaldo.js';

export async function gerarDashboardFinanceiro({ financeiroRepository, referencia, caixaIds = [] }) {
  if (!financeiroRepository) throw new Error('financeiroRepository é obrigatório.');
  const [receitas, despesas, transferencias] = await Promise.all([
    financeiroRepository.listarReceitas(),
    financeiroRepository.listarDespesas(),
    financeiroRepository.listarTransferencias ? financeiroRepository.listarTransferencias() : Promise.resolve([]),
  ]);
  return calcularResumoFinanceiro({ receitas, despesas, transferencias, referencia, caixaIds });
}
