-- Grupos gerenciais iniciais de despesas
-- Idempotente: não duplica grupos existentes na mesma empresa.

begin;

insert into public.grupos_gerenciais_despesas (
  empresa_id,
  nome,
  descricao,
  ordem,
  ativo
)
select
  e.id,
  g.nome,
  g.descricao,
  g.ordem,
  true
from public.empresas e
cross join (
  values
    ('Administrativas', 'Custos administrativos e de apoio à gestão.', 10),
    ('Operacionais', 'Custos recorrentes necessários ao funcionamento das atividades.', 20),
    ('Manutenção', 'Reparos, conservação e manutenção de bens e instalações.', 30),
    ('Missões', 'Despesas relacionadas a missões e apoio missionário.', 40),
    ('Assistência social', 'Ações sociais, auxílios e atendimento comunitário.', 50),
    ('Patrimônio', 'Aquisição, melhoria e conservação de bens patrimoniais.', 60),
    ('Eventos', 'Cultos especiais, congressos, conferências e outros eventos.', 70)
) as g(nome, descricao, ordem)
where not exists (
  select 1
  from public.grupos_gerenciais_despesas existente
  where existente.empresa_id = e.id
    and lower(trim(existente.nome)) = lower(trim(g.nome))
);

commit;
