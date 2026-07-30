export function LTModuleCard({ icon='📌', title, desc, color='blue', onClick, className = '' }) {
  const accentMap = { blue:'#1d78b6', green:'#16a34a', orange:'#f59e0b', purple:'#7c3aed', red:'#dc2626', slate:'#64748b', teal:'#0f9f9a', pink:'#db2777', dark:'#38bdf8' };
  const accent = accentMap[color] || color || accentMap.blue;
  const handleKeyDown = (e) => {
    if ((e.key === 'Enter' || e.key === ' ') && onClick) {
      e.preventDefault();
      onClick();
    }
  };
  return (
    <div className={`lt-module-card ${className}`.trim()} style={{ '--lt-card-accent': accent }} onClick={onClick} onKeyDown={handleKeyDown} role="button" tabIndex={0}>
      <div className="lt-module-card__icon">{icon}</div>
      <div className="lt-module-card__body">
        <h3>{title}</h3>
        <p>{desc}</p>
      </div>
    </div>
  );
}
