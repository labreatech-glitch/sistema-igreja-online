const keyOf = (value = '') =>
  String(value)
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_|_$/g, '');

export const normalizarCodigoEtiquetaPatrimonio = (value) => String(value ?? '').trim().toUpperCase();

export const codigosEtiquetaRepetidos = (values = []) => {
  const codes = values.map(normalizarCodigoEtiquetaPatrimonio).filter(Boolean);
  return new Set(codes.filter((code, index) => codes.indexOf(code) !== index));
};

export const patrimonioEstadoFromSheet = (value) => {
  const aliases = {
    novo: 'novo',
    nova: 'novo',
    bom: 'bom',
    boa: 'bom',
    regular: 'regular',
    ruim: 'ruim',
    inservivel: 'inservivel',
  };
  return aliases[keyOf(value)] || '';
};

export const patrimonioSheetHeader = (value = '') => {
  const key = keyOf(value);
  const aliases = {
    selo: 'codigo_etiqueta',
    codigo_selo: 'codigo_etiqueta',
    codigo_do_selo: 'codigo_etiqueta',
    etiqueta: 'codigo_etiqueta',
    codigo_etiqueta: 'codigo_etiqueta',
    codigo_da_etiqueta: 'codigo_etiqueta',
    bem: 'nome',
    nome: 'nome',
    nome_bem: 'nome',
    nome_do_bem: 'nome',
    categoria: 'categoria',
    local: 'local',
    departamento: 'local',
    local_departamento: 'local',
    congregacao: 'congregacao',
    descricao: 'descricao',
    descricao_observacoes: 'descricao',
    observacao: 'descricao',
    observacoes: 'descricao',
    marca: 'marca',
    modelo: 'modelo',
    numero_serie: 'numero_serie',
    numero_de_serie: 'numero_serie',
    serie: 'numero_serie',
    estado: 'estado_conservacao',
    conservacao: 'estado_conservacao',
    estado_conservacao: 'estado_conservacao',
    responsavel: 'responsavel',
    data_aquisicao: 'data_aquisicao',
    data_de_aquisicao: 'data_aquisicao',
    valor: 'valor_aquisicao',
    valor_aquisicao: 'valor_aquisicao',
    valor_de_aquisicao: 'valor_aquisicao',
  };
  return aliases[key] || key;
};
