import { validarMembroBasico } from '../../domain/secretaria/rules/normalizarMembro.js';

export async function cadastrarMembro({ membroRepository, membro }) {
  if (!membroRepository) throw new Error('membroRepository é obrigatório.');
  const validation = validarMembroBasico(membro);
  if (!validation.ok) throw new Error(validation.error);
  return membroRepository.criar(validation.value);
}
