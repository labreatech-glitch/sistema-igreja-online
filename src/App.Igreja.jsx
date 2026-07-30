import React, { useEffect, useMemo, useState } from 'react';
import { supabase, isSupabaseConfigured, getSupabaseDebugInfo } from './lib/supabase.js';

const moeda = (valor) => Number(valor || 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });

function Card({ title, value, hint }) {
  return <div className="igreja-card"><span>{title}</span><strong>{value}</strong>{hint && <small>{hint}</small>}</div>;
}

function Empty({ text }) { return <div className="igreja-empty">{text}</div>; }

function Login() {
  const [email, setEmail] = useState('labreatech@gmail.com');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const debug = getSupabaseDebugInfo();

  async function handleSubmit(e) {
    e.preventDefault();
    setError('');
    if (!isSupabaseConfigured || !supabase) {
      setError('Supabase não configurado. Confira o arquivo .env.');
      return;
    }
    setLoading(true);
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    setLoading(false);
    if (error) setError(error.message);
  }

  return <main className="igreja-login-page">
    <section className="igreja-login-brand">
      <div className="igreja-logo">⛪</div>
      <h1>Lábrea Tech Igreja</h1>
      <p>Financeiro, Secretaria, EBD e Patrimônio em uma plataforma simples para igrejas.</p>
      <div className="igreja-pill">✓ Livro Caixa por caixa</div>
      <div className="igreja-pill">✓ Controle de membros</div>
      <div className="igreja-pill">✓ Turmas e frequência EBD</div>
      <div className="igreja-pill">✓ Patrimônio da igreja</div>
    </section>
    <section className="igreja-login-card">
      <h2>Entrar</h2>
      <p>Acesse com o usuário criado no Supabase Auth.</p>
      {error && <div className="igreja-alert">{error}</div>}
      <form onSubmit={handleSubmit}>
        <label>E-mail</label>
        <input value={email} onChange={(e) => setEmail(e.target.value)} type="email" autoComplete="email" />
        <label>Senha</label>
        <input value={password} onChange={(e) => setPassword(e.target.value)} type="password" autoComplete="current-password" />
        <button disabled={loading}>{loading ? 'Entrando...' : 'Entrar'}</button>
      </form>
      <details className="igreja-debug">
        <summary>Diagnóstico da conexão</summary>
        <div>Configurado: {String(debug.configured)}</div>
        <div>URL: {debug.url}</div>
        <div>Chave: {debug.keyType} — {debug.keyPreview}</div>
      </details>
    </section>
  </main>;
}

function Dashboard({ session, onLogout }) {
  const [active, setActive] = useState('dashboard');
  const [dados, setDados] = useState({ caixas: [], membros: [], turmas: [], patrimonio: [], loading: true, error: '' });

  useEffect(() => {
    let alive = true;
    async function load() {
      setDados((d) => ({ ...d, loading: true, error: '' }));
      try {
        const [caixas, membros, turmas, patrimonio] = await Promise.all([
          supabase.from('vw_saldo_caixas_profissional').select('*').limit(20),
          supabase.from('membros').select('id,nome,telefone,email,situacao').limit(20),
          supabase.from('turmas_ebd').select('id,nome,professor,ativo').limit(20),
          supabase.from('patrimonio').select('id,nome,numero_patrimonio,status,valor_aquisicao').limit(20)
        ]);
        const err = caixas.error || membros.error || turmas.error || patrimonio.error;
        if (err) throw err;
        if (alive) setDados({ caixas: caixas.data || [], membros: membros.data || [], turmas: turmas.data || [], patrimonio: patrimonio.data || [], loading: false, error: '' });
      } catch (e) {
        if (alive) setDados((d) => ({ ...d, loading: false, error: e.message }));
      }
    }
    load();
    return () => { alive = false; };
  }, []);

  const saldoGeral = useMemo(() => dados.caixas.reduce((s, c) => s + Number(c.saldo_atual || c.saldo || 0), 0), [dados.caixas]);
  const menu = [
    ['dashboard', 'Dashboard'], ['financeiro', 'Financeiro'], ['secretaria', 'Secretaria'], ['ebd', 'EBD'], ['patrimonio', 'Patrimônio'], ['configuracoes', 'Configurações']
  ];

  return <div className="igreja-app">
    <aside className="igreja-sidebar">
      <div className="igreja-side-title"><div className="igreja-mini-logo">⛪</div><div><strong>Lábrea Tech</strong><span>Igreja v1.0</span></div></div>
      <nav>{menu.map(([id, label]) => <button key={id} onClick={() => setActive(id)} className={active === id ? 'active' : ''}>{label}</button>)}</nav>
    </aside>
    <section className="igreja-main">
      <header className="igreja-topbar"><div><span>PAINEL</span><h1>{menu.find((m) => m[0] === active)?.[1]}</h1></div><div className="igreja-user"><span>{session.user.email}</span><button onClick={onLogout}>Sair</button></div></header>
      {dados.error && <div className="igreja-alert">{dados.error}</div>}
      {active === 'dashboard' && <>
        <div className="igreja-grid"><Card title="Saldo Geral" value={moeda(saldoGeral)} /><Card title="Caixas" value={dados.caixas.length} /><Card title="Membros" value={dados.membros.length} /><Card title="Turmas EBD" value={dados.turmas.length} /><Card title="Patrimônio" value={dados.patrimonio.length} /></div>
        <div className="igreja-panel"><h2>Saldos por caixa</h2>{dados.caixas.length ? <table><thead><tr><th>Caixa</th><th>Entradas</th><th>Saídas</th><th>Saldo</th></tr></thead><tbody>{dados.caixas.map(c => <tr key={c.caixa_id}><td>{c.caixa}</td><td>{moeda(c.entradas)}</td><td>{moeda(c.saidas)}</td><td>{moeda(c.saldo_atual || c.saldo)}</td></tr>)}</tbody></table> : <Empty text="Nenhum saldo encontrado." />}</div>
      </>}
      {active === 'financeiro' && <div className="igreja-panel"><h2>Financeiro</h2><p>Próximo patch: Livro Caixa, receitas, despesas e transferências.</p></div>}
      {active === 'secretaria' && <div className="igreja-panel"><h2>Membros</h2>{dados.membros.length ? <table><thead><tr><th>Nome</th><th>Telefone</th><th>Situação</th></tr></thead><tbody>{dados.membros.map(m => <tr key={m.id}><td>{m.nome}</td><td>{m.telefone}</td><td>{m.situacao}</td></tr>)}</tbody></table> : <Empty text="Nenhum membro cadastrado." />}</div>}
      {active === 'ebd' && <div className="igreja-panel"><h2>Turmas EBD</h2>{dados.turmas.length ? <table><thead><tr><th>Turma</th><th>Professor</th><th>Ativo</th></tr></thead><tbody>{dados.turmas.map(t => <tr key={t.id}><td>{t.nome}</td><td>{t.professor}</td><td>{t.ativo ? 'Sim' : 'Não'}</td></tr>)}</tbody></table> : <Empty text="Nenhuma turma cadastrada." />}</div>}
      {active === 'patrimonio' && <div className="igreja-panel"><h2>Patrimônio</h2>{dados.patrimonio.length ? <table><thead><tr><th>Nº</th><th>Bem</th><th>Status</th><th>Valor</th></tr></thead><tbody>{dados.patrimonio.map(p => <tr key={p.id}><td>{p.numero_patrimonio}</td><td>{p.nome}</td><td>{p.status}</td><td>{moeda(p.valor_aquisicao)}</td></tr>)}</tbody></table> : <Empty text="Nenhum patrimônio cadastrado." />}</div>}
      {active === 'configuracoes' && <div className="igreja-panel"><h2>Configurações</h2><p>Caixas, categorias, formas de pagamento, usuários e perfis.</p></div>}
    </section>
  </div>;
}

export default function AppIgreja() {
  const [session, setSession] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase) { setLoading(false); return; }
    supabase.auth.getSession().then(({ data }) => { setSession(data.session); setLoading(false); });
    const { data: sub } = supabase.auth.onAuthStateChange((_event, nextSession) => setSession(nextSession));
    return () => sub.subscription.unsubscribe();
  }, []);

  async function logout() { await supabase.auth.signOut(); setSession(null); }
  if (loading) return <div className="igreja-loading">Carregando...</div>;
  return session ? <Dashboard session={session} onLogout={logout} /> : <Login />;
}
