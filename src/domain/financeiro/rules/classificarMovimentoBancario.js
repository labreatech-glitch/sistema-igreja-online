const RULES = [
  { match: ['TAR.', 'TARIFA', 'IOF', 'JUROS'], tipo: 'Despesa', categoria: 'Tarifas Bancárias' },
  { match: ['PIX RECEBIDO', 'CREDITO PIX', 'TRANSFERENCIA RECEBIDA', 'DEPÓSITO', 'DEPOSITO'], tipo: 'Receita', categoria: 'Entrada Bancária' },
  { match: ['PIX ENVIADO', 'PAGAMENTO', 'DEBITO', 'DÉBITO'], tipo: 'Despesa', categoria: 'Despesas Bancárias' },
];

export function classificarMovimentoBancario(historico = '', valor = 0) {
  const text = String(historico || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toUpperCase();
  const explicit = RULES.find(rule => rule.match.some(term => text.includes(term.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toUpperCase())));
  if (explicit) return { tipo: explicit.tipo, categoria: explicit.categoria, regra: 'historico' };
  const tipo = Number(valor) < 0 ? 'Despesa' : 'Receita';
  return { tipo, categoria: tipo === 'Receita' ? 'Entrada Bancária' : 'Despesas Bancárias', regra: 'valor' };
}

export function identificarPessoaPix(historico = '') {
  const text = String(historico || '').replace(/\s+/g, ' ').trim();
  if (!/PIX/i.test(text)) return { nome: '', documento: '', hora: '' };

  let rest = text
    .replace(/^.*?PIX\s*-?\s*(RECEBIDO|ENVIADO|RECEBIDO QR CODE|ENVIADO QR CODE)?\s*-?\s*/i, '')
    .replace(/^[^0-9A-ZÀ-Ú]+/i, '')
    .trim();

  const dataMatch = rest.match(/^(\d{2}\/\d{2})\s*/);
  if (dataMatch) rest = rest.slice(dataMatch[0].length).trim();

  let hora = '';
  const horaMatch = rest.match(/^(\d{2}:\d{2})\s*/);
  if (horaMatch) {
    hora = horaMatch[1];
    rest = rest.slice(horaMatch[0].length).trim();
  }

  let documento = '';
  const docMatch = rest.match(/^([0-9.\-]{5,})\s+/);
  if (docMatch) {
    documento = docMatch[1];
    rest = rest.slice(docMatch[0].length).trim();
  }

  const nome = rest.replace(/\s*-\s*OCORR[EÊ]NCIA.*$/i, '').trim();
  return { nome, documento, hora };
}
