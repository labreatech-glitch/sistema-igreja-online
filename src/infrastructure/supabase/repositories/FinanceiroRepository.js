export function createFinanceiroRepository(supabase, empresaId) {
  const byEmpresa = (query) => empresaId ? query.eq('empresa_id', empresaId) : query;
  return {
    async listarReceitas() {
      const { data, error } = await byEmpresa(supabase.from('lancamentos_financeiros').select('*'));
      if (error) throw error;
      return data || [];
    },
    async listarDespesas() {
      const { data, error } = await byEmpresa(supabase.from('despesas').select('*'));
      if (error) throw error;
      return data || [];
    },
    async listarTransferencias() {
      const { data, error } = await byEmpresa(supabase.from('transferencias_caixas').select('*'));
      if (error) throw error;
      return data || [];
    },
    async importarMovimentos(movimentos) {
      // Ponto único para evoluir importação com RPC transacional no futuro.
      const receitas = movimentos.filter(m => m.tipo === 'Receita');
      const despesas = movimentos.filter(m => m.tipo === 'Despesa');
      const results = { receitas: [], despesas: [] };
      if (receitas.length) {
        const { data, error } = await supabase.from('lancamentos_financeiros').insert(receitas).select('*');
        if (error) throw error;
        results.receitas = data || [];
      }
      if (despesas.length) {
        const { data, error } = await supabase.from('despesas').insert(despesas).select('*');
        if (error) throw error;
        results.despesas = data || [];
      }
      return results;
    },
  };
}
