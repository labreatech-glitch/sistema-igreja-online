-- Catálogo gerencial ampliado para igrejas
-- Versão 2.32.8
-- Idempotente: atualiza a descrição/ordem dos grupos padronizados e insere os ausentes.
-- Não altera grupos personalizados que tenham outros nomes.
-- Os grupos são sugestões gerenciais, não substituem o plano de contas contábil definido pelo contador.

begin;

create temporary table catalogo_grupos_igreja (
  nome text primary key,
  descricao text not null,
  ordem integer not null
) on commit drop;

insert into catalogo_grupos_igreja (nome, descricao, ordem) values
  ('Administrativas', 'Rotinas administrativas, expediente e apoio geral à gestão. Exemplo: compra de papel, toner e material de escritório.', 10),
  ('Governança e conformidade', 'Assembleias, conselhos, documentação institucional e obrigações legais. Exemplo: honorários contábeis ou registro de ata em cartório.', 20),
  ('Pessoal e encargos', 'Remuneração, prebendas, benefícios, encargos e capacitação de colaboradores. Exemplo: salário de secretário ou recolhimento de INSS.', 30),
  ('Operacionais', 'Custos cotidianos necessários ao funcionamento geral da igreja. Exemplo: material de limpeza e itens de consumo diário.', 40),
  ('Instalações e utilidades', 'Custos de uso dos imóveis e serviços essenciais. Exemplo: aluguel, energia elétrica, água ou gás.', 50),
  ('Manutenção', 'Conservação preventiva e corretiva de imóveis, máquinas e equipamentos. Exemplo: conserto de ar-condicionado ou reparo elétrico.', 60),
  ('Patrimônio', 'Aquisição, melhoria e conservação de bens duráveis. Exemplo: compra de cadeiras, instrumentos ou projetor.', 70),
  ('Tecnologia e comunicação', 'Internet, telefonia, softwares, equipamentos de TI, transmissão e divulgação institucional. Exemplo: mensalidade de software, internet ou câmera para transmissão.', 80),
  ('Cultos e liturgia', 'Materiais e serviços diretamente relacionados às celebrações e ordenanças. Exemplo: elementos da ceia, material para batismo ou decoração do templo.', 90),
  ('Louvor e música', 'Despesas específicas do ministério de louvor, coral e atividades musicais. Exemplo: manutenção de instrumentos, cabos ou partituras.', 100),
  ('Educação cristã e discipulado', 'EBD, estudos bíblicos, formação, literatura e ações de discipulado. Exemplo: revistas da EBD, livros ou material de curso.', 110),
  ('Ministérios e departamentos', 'Apoio a ministérios de crianças, adolescentes, jovens, mulheres, homens, famílias e outros departamentos. Exemplo: material para uma atividade do ministério infantil.', 120),
  ('Missões', 'Sustento missionário e projetos de missões locais, nacionais e internacionais. Exemplo: oferta mensal a missionário ou passagem para viagem missionária.', 130),
  ('Evangelismo', 'Campanhas, visitas e ações de proclamação e alcance comunitário. Exemplo: impressão de folhetos ou locação de estrutura para cruzada evangelística.', 140),
  ('Assistência social', 'Beneficência, auxílios emergenciais e atendimento social à comunidade. Exemplo: compra de cestas básicas, medicamentos ou auxílio funeral.', 150),
  ('Eventos', 'Congressos, conferências, retiros, encontros e programações especiais. Exemplo: aluguel de espaço, alimentação ou material para congresso.', 160),
  ('Comunhão e integração', 'Recepção, confraternização, integração de membros, voluntariado e cuidado comunitário. Exemplo: lanche de integração de novos membros.', 170),
  ('Transporte e logística', 'Deslocamento de pessoas, materiais e apoio logístico às atividades. Exemplo: combustível, frete ou aluguel de ônibus.', 180),
  ('Segurança e prevenção', 'Proteção de pessoas, imóveis e atendimento a requisitos preventivos. Exemplo: vigilância, extintores, câmeras ou laudo de segurança.', 190),
  ('Captação de recursos', 'Campanhas de arrecadação e custos diretamente relacionados à obtenção de recursos. Exemplo: material para bazar ou taxa de plataforma de doação.', 200),
  ('Projetos, obras e expansão', 'Construções, reformas estruturais e implantação de novas unidades. Exemplo: compra de cimento para ampliação do templo.', 210),
  ('Congregações e campos', 'Apoio financeiro e operacional a congregações, pontos de pregação e campos vinculados. Exemplo: repasse mensal para uma congregação.', 220),
  ('Serviços profissionais', 'Serviços técnicos especializados não enquadrados em outro grupo. Exemplo: honorários de advogado, engenheiro, auditor ou consultor.', 230),
  ('Taxas bancárias e financeiras', 'Tarifas bancárias, meios de pagamento e custos financeiros. Exemplo: tarifa de manutenção de conta ou taxa de cobrança.', 240),
  ('Seguros, licenças e tributos', 'Seguros, licenças, taxas públicas e tributos eventualmente devidos. Exemplo: seguro predial, alvará ou taxa municipal.', 250),
  ('Reserva e contingência', 'Recursos destinados a emergências, imprevistos e recomposição de reservas. Exemplo: provisão para reparo emergencial do telhado.', 260);

-- Atualiza apenas os grupos do catálogo, preservando nome e identidade do registro.
update public.grupos_gerenciais_despesas g
set descricao = c.descricao,
    ordem = c.ordem,
    updated_at = now()
from catalogo_grupos_igreja c
where lower(trim(g.nome)) = lower(trim(c.nome));

-- Insere os grupos ainda inexistentes em cada empresa.
insert into public.grupos_gerenciais_despesas (
  empresa_id, nome, descricao, ordem, ativo
)
select e.id, c.nome, c.descricao, c.ordem, true
from public.empresas e
cross join catalogo_grupos_igreja c
where not exists (
  select 1
  from public.grupos_gerenciais_despesas existente
  where existente.empresa_id = e.id
    and lower(trim(existente.nome)) = lower(trim(c.nome))
);

commit;
