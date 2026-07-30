const MESES = ['Janeiro','Fevereiro','Março','Abril','Maio','Junho','Julho','Agosto','Setembro','Outubro','Novembro','Dezembro'];

export function currentReferencia(now = new Date()) {
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
}

export function referenciaFromDate(dateLike, fallback = new Date()) {
  if (!dateLike) return currentReferencia(fallback);
  const text = String(dateLike).trim();
  if (/^\d{4}-\d{2}/.test(text)) return text.slice(0, 7);
  if (/^\d{2}\/\d{2}\/\d{4}$/.test(text)) {
    const [, mes, ano] = text.split('/');
    return `${ano}-${mes}`;
  }
  const d = new Date(text);
  if (!Number.isNaN(d.getTime())) return currentReferencia(d);
  return currentReferencia(fallback);
}

export function ensureReferencia(value, fallbackDate) {
  const raw = String(value || '').trim();
  if (/^\d{4}-\d{2}$/.test(raw)) return raw;
  if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) return raw.slice(0, 7);
  if (/^\d{2}\/\d{4}$/.test(raw)) {
    const [mes, ano] = raw.split('/');
    return `${ano}-${mes}`;
  }
  const normalized = raw.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
  const match = normalized.match(/(janeiro|fevereiro|marco|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro)\s*(de)?\s*(\d{4})/);
  if (match) {
    const meses = ['janeiro','fevereiro','marco','abril','maio','junho','julho','agosto','setembro','outubro','novembro','dezembro'];
    const mes = String(meses.indexOf(match[1]) + 1).padStart(2, '0');
    return `${match[3]}-${mes}`;
  }
  return referenciaFromDate(fallbackDate);
}

export function formatReferencia(ref) {
  const [ano, mes] = ensureReferencia(ref).split('-');
  const label = MESES[Number(mes) - 1];
  return label ? `${label}/${ano}` : ref;
}
