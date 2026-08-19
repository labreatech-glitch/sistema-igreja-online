-- v2.42.0 — Plano de Contas Estruturado
-- Importação transacional, clonagem segura e proteção de exclusão.
begin;

create or replace function public.contabil_importar_plano_contas(
  p_empresa_id uuid,
  p_contas jsonb,
  p_modo text default 'mesclar'
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item jsonb;
  v_pai_id uuid;
  v_ref_id uuid;
  v_codigo text;
  v_existente uuid;
  v_inseridas int := 0;
  v_ignoradas int := 0;
  v_nao_base int := 0;
begin
  if p_empresa_id is null then raise exception 'Empresa não informada.'; end if;
  if jsonb_typeof(p_contas) <> 'array' then raise exception 'Estrutura do plano inválida.'; end if;
  if p_modo not in ('mesclar','vazio') then raise exception 'Modo de importação inválido.'; end if;
  if not (public.is_master() or (public.is_ativo() and p_empresa_id = public.current_empresa_id() and public.current_role() in ('admin','tesoureiro'))) then
    raise exception 'Usuário sem permissão para importar o plano de contas.';
  end if;
  if p_modo = 'vazio' then
    select count(*) into v_nao_base from public.contabil_plano_contas where empresa_id=p_empresa_id and codigo not in ('1','2','3','4','5','9');
    if v_nao_base > 0 then raise exception 'O plano já possui contas além da estrutura-base. Use a opção Mesclar.'; end if;
  end if;

  for v_item in select value from jsonb_array_elements(p_contas) loop
    v_codigo := btrim(coalesce(v_item->>'codigo',''));
    if v_codigo = '' or btrim(coalesce(v_item->>'nome','')) = '' then raise exception 'Código e nome são obrigatórios em todas as contas.'; end if;
    if coalesce(v_item->>'tipo','') not in ('ativo','passivo','patrimonio_social','receita','despesa','compensacao') then raise exception 'Tipo inválido na conta %.', v_codigo; end if;
    if coalesce(v_item->>'natureza','') not in ('devedora','credora') then raise exception 'Natureza inválida na conta %.', v_codigo; end if;
    select id into v_existente from public.contabil_plano_contas where empresa_id=p_empresa_id and codigo=v_codigo;
    if v_existente is not null then v_ignoradas := v_ignoradas + 1; continue; end if;
    v_pai_id := null;
    if nullif(btrim(coalesce(v_item->>'conta_pai_codigo','')),'') is not null then
      select id into v_pai_id from public.contabil_plano_contas where empresa_id=p_empresa_id and codigo=btrim(v_item->>'conta_pai_codigo');
      if v_pai_id is null then raise exception 'Conta superior % não encontrada para a conta %.', v_item->>'conta_pai_codigo', v_codigo; end if;
      if exists(select 1 from public.contabil_plano_contas where id=v_pai_id and analitica) then raise exception 'Conta superior % é analítica e não pode receber a conta %.', v_item->>'conta_pai_codigo', v_codigo; end if;
    end if;
    v_ref_id := null;
    if nullif(btrim(coalesce(v_item->>'conta_referencial_codigo','')),'') is not null then
      select id into v_ref_id from public.contabil_contas_referenciais where empresa_id=p_empresa_id and codigo=btrim(v_item->>'conta_referencial_codigo') order by ano_inicio desc nulls last limit 1;
      if v_ref_id is null then raise exception 'Conta referencial % não encontrada para a conta %.', v_item->>'conta_referencial_codigo', v_codigo; end if;
    end if;
    insert into public.contabil_plano_contas(empresa_id,codigo,nome,conta_pai_id,tipo,natureza,analitica,conta_referencial_id,observacoes,ativo,created_by)
    values(p_empresa_id,v_codigo,btrim(v_item->>'nome'),v_pai_id,v_item->>'tipo',v_item->>'natureza',coalesce((v_item->>'analitica')::boolean,true),v_ref_id,nullif(v_item->>'observacoes',''),true,auth.uid());
    v_inseridas := v_inseridas + 1;
  end loop;
  return jsonb_build_object('inseridas',v_inseridas,'ignoradas',v_ignoradas);
end;
$$;

create or replace function public.contabil_clonar_plano_contas(
  p_empresa_origem uuid,
  p_empresa_destino uuid,
  p_modo text default 'vazio'
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_payload jsonb;
begin
  if not public.is_master() then raise exception 'Somente o administrador master pode clonar plano entre empresas.'; end if;
  if p_empresa_origem is null or p_empresa_destino is null or p_empresa_origem=p_empresa_destino then raise exception 'Empresas de origem e destino inválidas.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'codigo',c.codigo,'nome',c.nome,'conta_pai_codigo',p.codigo,'tipo',c.tipo,'natureza',c.natureza,'analitica',c.analitica,'observacoes',c.observacoes
  ) order by c.codigo),'[]'::jsonb) into v_payload
  from public.contabil_plano_contas c left join public.contabil_plano_contas p on p.id=c.conta_pai_id
  where c.empresa_id=p_empresa_origem;
  return public.contabil_importar_plano_contas(p_empresa_destino,v_payload,p_modo);
end;
$$;

create or replace function public.proteger_exclusao_conta_contabil()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists(select 1 from public.contabil_plano_contas where conta_pai_id=old.id) then raise exception 'Conta possui contas filhas. Inative-a ou reorganize a estrutura antes de excluir.'; end if;
  if exists(select 1 from public.contabil_partidas where conta_contabil_id=old.id) then raise exception 'Conta possui movimentação contábil e não pode ser excluída. Inative-a para preservar o histórico.'; end if;
  if exists(select 1 from public.categorias_despesas where conta_contabil_id=old.id) or exists(select 1 from public.tipos_receita where conta_contabil_id=old.id) or exists(select 1 from public.tipos_caixa where conta_contabil_id=old.id) then raise exception 'Conta possui vínculos financeiros. Remova os vínculos ou inative a conta.'; end if;
  return old;
end;
$$;

drop trigger if exists trg_proteger_exclusao_conta_contabil on public.contabil_plano_contas;
create trigger trg_proteger_exclusao_conta_contabil before delete on public.contabil_plano_contas for each row execute function public.proteger_exclusao_conta_contabil();


create or replace function public.validar_hierarquia_plano_contas()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pai_empresa uuid;
  v_pai_analitica boolean;
begin
  if new.conta_pai_id is not null then
    select empresa_id, analitica into v_pai_empresa, v_pai_analitica from public.contabil_plano_contas where id=new.conta_pai_id;
    if v_pai_empresa is null or v_pai_empresa <> new.empresa_id then raise exception 'A conta superior deve pertencer à mesma empresa.'; end if;
    if v_pai_analitica then raise exception 'Uma conta analítica não pode receber contas filhas. Torne a conta superior sintética antes de continuar.'; end if;
    if new.id is not null and exists(
      with recursive ancestrais as (
        select id, conta_pai_id from public.contabil_plano_contas where id=new.conta_pai_id
        union all
        select p.id,p.conta_pai_id from public.contabil_plano_contas p join ancestrais a on p.id=a.conta_pai_id
      ) select 1 from ancestrais where id=new.id
    ) then raise exception 'A hierarquia criaria um ciclo entre contas.'; end if;
  end if;
  if new.analitica and new.id is not null and exists(select 1 from public.contabil_plano_contas where conta_pai_id=new.id) then
    raise exception 'Conta com filhas não pode ser marcada como analítica.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validar_hierarquia_plano_contas on public.contabil_plano_contas;
create trigger trg_validar_hierarquia_plano_contas
before insert or update of conta_pai_id, analitica, empresa_id on public.contabil_plano_contas
for each row execute function public.validar_hierarquia_plano_contas();

grant execute on function public.contabil_importar_plano_contas(uuid,jsonb,text) to authenticated;
grant execute on function public.contabil_clonar_plano_contas(uuid,uuid,text) to authenticated;

commit;
