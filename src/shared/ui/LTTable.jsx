export function LTTable({ columns = [], rows = [], empty = 'Nenhum registro encontrado.' }) {
  return <div className="lt-table-wrap"><table className="lt-table"><thead><tr>{columns.map(c => <th key={c.key || c}>{c.label || c}</th>)}</tr></thead><tbody>{rows.length ? rows.map((row, idx) => <tr key={row.id || idx}>{columns.map(c => <td key={c.key || c}>{typeof c.render === 'function' ? c.render(row) : row[c.key || c]}</td>)}</tr>) : <tr><td colSpan={columns.length}>{empty}</td></tr>}</tbody></table></div>;
}
