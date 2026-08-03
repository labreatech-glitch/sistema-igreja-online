# Supabase - Sistema Igreja

Use esta pasta para organizar os scripts SQL do sistema igreja.

O projeto correto no Supabase é: sistema-igreja.
Não execute estes scripts no projeto da transportadora.

## Atualizacao segura em sistema existente

Em ambiente com dados reais, nao execute scripts de reset/recriacao do schema
para atualizar o sistema. Os scripts `schema.sql`,
`00_EXECUTE_PRIMEIRO_SCHEMA_COMPLETO.sql` e `00_RESET_SCHEMA_LIMPO_SAAS.sql`
sao destrutivos e agora exigem confirmacao explicita na sessao SQL antes de
apagar o schema `public`.

Para producao, use somente scripts incrementais e idempotentes, conferindo a
ordem de versao e fazendo backup antes de qualquer mudanca de banco.

Scripts incrementais mais recentes:

- `58_ALINHAR_PERFIS_PERMISSOES_RLS.sql`: alinha os perfis `secretario`,
  `tesoureiro` e `membro` entre frontend e banco, recriando policies
  operacionais por modulo sem remover dados.
- `59_ALINHAR_CONFIGURACOES_PERMISSOES_PADRAO.sql`: completa configuracoes
  antigas de permissoes em `app_configuracoes` sem sobrescrever
  personalizacoes existentes.

Checklist minimo antes de atualizar:

1. confirme que o projeto Supabase e o `sistema-igreja`;
2. faca backup/exportacao dos dados;
3. execute apenas o script incremental necessario;
4. valide login, permissoes, financeiro, relatorios e importacoes;
5. guarde o script aplicado e a data da aplicacao.

Para reset completo em desenvolvimento, execute conscientemente na mesma sessao:

```sql
set app.allow_destructive_schema_reset = 'true';
-- depois execute o script de reset desejado
```
