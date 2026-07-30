export function LTButton({ children, variant = 'primary', size = 'md', className = '', ...props }) {
  return <button className={`lt-btn lt-btn--${variant} lt-btn--${size} ${className}`.trim()} {...props}>{children}</button>;
}
