export function LTPage({ eyebrow, title, subtitle, icon, children }) {
  return <div className="lt-page"><header className="lt-page-header">{icon && <span className="lt-page-icon">{icon}</span>}<div>{eyebrow && <small>{eyebrow}</small>}<h1>{title}</h1>{subtitle && <p>{subtitle}</p>}</div></header>{children}</div>;
}
