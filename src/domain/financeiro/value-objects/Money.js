export function toCents(value) {
  if (value == null || value === '') return 0;
  if (typeof value === 'number') return Math.round(value * 100);
  const text = String(value).trim().replace(/\s/g, '');
  const normalized = text
    .replace(/R\$/gi, '')
    .replace(/\./g, '')
    .replace(',', '.');
  const n = Number(normalized);
  return Number.isFinite(n) ? Math.round(n * 100) : 0;
}

export function fromCents(cents) {
  return Math.round(Number(cents || 0)) / 100;
}

export function money(value) {
  return fromCents(toCents(value));
}

export function formatMoney(value) {
  return money(value).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
}
