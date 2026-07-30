export function LTStatCard({ label, value, accent = '#1d78b6' }) {
  return <div className="lt-stat-card" style={{ '--lt-stat-accent': accent }}><span>{label}</span><strong>{value}</strong></div>;
}
