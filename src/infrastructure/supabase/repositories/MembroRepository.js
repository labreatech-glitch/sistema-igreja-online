export function createMembroRepository(supabase, empresaId) {
  return {
    async criar(membro) {
      const payload = empresaId ? { ...membro, empresa_id: empresaId } : membro;
      const { data, error } = await supabase.from('membros').insert(payload).select('*').single();
      if (error) throw error;
      return data;
    },
  };
}
