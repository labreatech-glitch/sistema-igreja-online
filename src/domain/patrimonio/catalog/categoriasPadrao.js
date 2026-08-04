export const PATRIMONIO_CATEGORIAS_PADRAO = Object.freeze([
  {
    nome: 'Terrenos',
    descricao: 'Terrenos e áreas sem edificação. Normalmente não sujeitos à depreciação.',
    depreciavel: false,
    vida_util_meses: null,
    valor_residual_percentual: 0,
    observacao: 'Não depreciar; avaliar separadamente eventuais edificações e benfeitorias.',
  },
  {
    nome: 'Templos, prédios e edificações',
    descricao: 'Templos, prédios administrativos, casas pastorais, salões e edificações concluídas.',
    depreciavel: true,
    vida_util_meses: 300,
    valor_residual_percentual: 10,
    observacao: 'Referência inicial de 25 anos; validar componentes e vida útil com o contador.',
  },
  {
    nome: 'Benfeitorias e instalações',
    descricao: 'Reformas incorporadas, instalações elétricas, hidráulicas e benfeitorias permanentes.',
    depreciavel: true,
    vida_util_meses: 120,
    valor_residual_percentual: 5,
    observacao: 'Separar da edificação quando possuir vida útil diferente.',
  },
  {
    nome: 'Móveis e utensílios',
    descricao: 'Mesas, cadeiras, armários, púlpitos, bancos e utensílios de uso duradouro.',
    depreciavel: true,
    vida_util_meses: 120,
    valor_residual_percentual: 5,
    observacao: 'Referência inicial de 10 anos.',
  },
  {
    nome: 'Equipamentos de informática',
    descricao: 'Computadores, notebooks, servidores, impressoras e periféricos relevantes.',
    depreciavel: true,
    vida_util_meses: 60,
    valor_residual_percentual: 5,
    observacao: 'Referência inicial de 5 anos; revisar conforme obsolescência e uso.',
  },
  {
    nome: 'Celulares e tablets',
    descricao: 'Celulares, smartphones e tablets pertencentes à igreja.',
    depreciavel: true,
    vida_util_meses: 60,
    valor_residual_percentual: 5,
    observacao: 'Referência inicial de 5 anos; revisar conforme uso e obsolescência.',
  },
  {
    nome: 'Som e áudio',
    descricao: 'Mesas de som, caixas acústicas, microfones, amplificadores e processadores de áudio.',
    depreciavel: true,
    vida_util_meses: 120,
    valor_residual_percentual: 5,
    observacao: 'Referência inicial de 10 anos.',
  },
  {
    nome: 'Projetores, TVs e multimídia',
    descricao: 'Projetores, televisores, painéis, câmeras e equipamentos de transmissão.',
    depreciavel: true,
    vida_util_meses: 120,
    valor_residual_percentual: 5,
    observacao: 'Revisar itens sujeitos a obsolescência tecnológica acelerada.',
  },
  {
    nome: 'Instrumentos musicais',
    descricao: 'Teclados, pianos, baterias, violões, guitarras, baixos e instrumentos de sopro.',
    depreciavel: true,
    vida_util_meses: 120,
    valor_residual_percentual: 10,
    observacao: 'Considerar conservação, possibilidade de revenda e valor histórico.',
  },
  {
    nome: 'Iluminação',
    descricao: 'Refletores, controladores, mesas de luz e equipamentos de iluminação cênica.',
    depreciavel: true,
    vida_util_meses: 120,
    valor_residual_percentual: 5,
    observacao: 'Referência inicial de 10 anos.',
  },
  {
    nome: 'Ar-condicionado e climatização',
    descricao: 'Aparelhos de ar-condicionado, climatizadores e sistemas de ventilação.',
    depreciavel: true,
    vida_util_meses: 120,
    valor_residual_percentual: 5,
    observacao: 'A manutenção pode alterar a vida útil esperada.',
  },
  {
    nome: 'Eletrodomésticos',
    descricao: 'Geladeiras, freezers, fogões, bebedouros, lavadoras e eletrodomésticos em geral.',
    depreciavel: true,
    vida_util_meses: 120,
    valor_residual_percentual: 5,
    observacao: 'Referência inicial de 10 anos.',
  },
  {
    nome: 'Equipamentos de cozinha',
    descricao: 'Equipamentos industriais e utensílios duráveis utilizados em cozinhas e refeitórios.',
    depreciavel: true,
    vida_util_meses: 120,
    valor_residual_percentual: 5,
    observacao: 'Distinguir utensílios de consumo dos bens duráveis.',
  },
  {
    nome: 'Segurança e monitoramento',
    descricao: 'Câmeras, gravadores, alarmes, controles de acesso e equipamentos de segurança.',
    depreciavel: true,
    vida_util_meses: 60,
    valor_residual_percentual: 5,
    observacao: 'Referência inicial de 5 anos por obsolescência tecnológica.',
  },
  {
    nome: 'Máquinas, ferramentas e equipamentos',
    descricao: 'Máquinas, ferramentas elétricas e equipamentos operacionais não classificados em outro grupo.',
    depreciavel: true,
    vida_util_meses: 120,
    valor_residual_percentual: 5,
    observacao: 'Revisar de acordo com intensidade de uso e especificação do fabricante.',
  },
  {
    nome: 'Veículos',
    descricao: 'Automóveis, motocicletas, vans, ônibus e outros veículos da igreja.',
    depreciavel: true,
    vida_util_meses: 60,
    valor_residual_percentual: 20,
    observacao: 'Referência inicial de 5 anos; estimar residual conforme conservação e mercado.',
  },
  {
    nome: 'Geradores e sistemas de energia',
    descricao: 'Geradores, nobreaks de grande porte, sistemas solares e equipamentos de energia.',
    depreciavel: true,
    vida_util_meses: 120,
    valor_residual_percentual: 10,
    observacao: 'Separar componentes com vidas úteis relevantes quando necessário.',
  },
  {
    nome: 'Acervo bibliográfico',
    descricao: 'Livros, coleções e materiais bibliográficos controlados como patrimônio.',
    depreciavel: true,
    vida_util_meses: 120,
    valor_residual_percentual: 0,
    observacao: 'A política contábil pode determinar tratamento diferente; validar antes do fechamento.',
  },
  {
    nome: 'Obras de arte e acervo histórico',
    descricao: 'Peças artísticas, históricas, raras ou de coleção mantidas pela igreja.',
    depreciavel: false,
    vida_util_meses: null,
    valor_residual_percentual: 0,
    observacao: 'Não depreciar automaticamente; avaliar individualmente com o contador.',
  },
  {
    nome: 'Construções em andamento',
    descricao: 'Obras ainda não concluídas ou disponíveis para uso.',
    depreciavel: false,
    vida_util_meses: null,
    valor_residual_percentual: 0,
    observacao: 'Iniciar a depreciação somente quando a obra estiver concluída e disponível para uso.',
  },
]);

export const normalizarNomeCategoriaPatrimonio = (value = '') => String(value || '')
  .normalize('NFD')
  .replace(/[\u0300-\u036f]/g, '')
  .trim()
  .replace(/\s+/g, ' ')
  .toLocaleLowerCase('pt-BR');

export function categoriasPatrimonioPadraoAusentes(categoriasExistentes = []) {
  const existentes = new Set((categoriasExistentes || []).map((categoria) => normalizarNomeCategoriaPatrimonio(categoria?.nome)));
  return PATRIMONIO_CATEGORIAS_PADRAO.filter((categoria) => !existentes.has(normalizarNomeCategoriaPatrimonio(categoria.nome)));
}
