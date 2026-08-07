-- 77_CONTABILIDADE_VINCULOS_LANCAMENTOS_FUNCIONAIS.sql
-- Completa os pré-requisitos operacionais de vínculos e lançamentos contábeis.
-- Aditiva, multi-tenant e sem reclassificação automática de movimentos antigos.
begin;

-- Contas analíticas mínimas para permitir vínculos e testes iniciais.
-- A estrutura deve ser revisada pelo contador responsável antes do uso oficial.
insert into public.contabil_plano_contas
  (empresa_id, codigo, nome, conta_pai_id, tipo, natureza, analitica, ativo, observacoes)
select e.id, x.codigo, x.nome, pai.id, x.tipo, x.natureza, true, true,
       'Conta analítica inicial sugerida. Validar com o contador responsável.'
from public.empresas e
cross join (values
  ('1.1.01.001','Caixa geral','1','ativo','devedora'),
  ('1.1.02.001','Bancos conta movimento','1','ativo','devedora'),
  ('2.1.01.001','Fornecedores e obrigações a pagar','2','passivo','credora'),
  ('3.1.01.001','Patrimônio social','3','patrimonio_social','credora'),
  ('4.1.01.001','Dízimos e contribuições','4','receita','credora'),
  ('4.1.02.001','Ofertas e doações','4','receita','credora'),
  ('5.1.01.001','Despesas administrativas','5','despesa','devedora'),
  ('5.1.02.001','Despesas operacionais','5','despesa','devedora')
) as x(codigo,nome,pai_codigo,tipo,natureza)
join public.contabil_plano_contas pai
  on pai.empresa_id=e.id and pai.codigo=x.pai_codigo
on conflict (empresa_id,codigo) do nothing;

-- Salva vínculos por RPC para manter escopo, autorização e tabela permitida no backend.
create or replace function public.salvar_vinculo_contabil(
  p_tabela text,
  p_registro_id uuid,
  p_conta_contabil_id uuid
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_empresa uuid := public.current_empresa_id();
  v_conta_empresa uuid;
  v_analitica boolean;
  v_sql text;
begin
  if not (public.is_master() or (public.is_ativo() and public.current_role() in ('admin','tesoureiro'))) then
    raise exception 'Sem permissão para alterar vínculos contábeis.';
  end if;
  if p_tabela not in ('categorias_despesas','tipos_receita','tipos_caixa') then
    raise exception 'Cadastro financeiro não permitido para vínculo contábil.';
  end if;
  if p_conta_contabil_id is not null then
    select empresa_id,analitica into v_conta_empresa,v_analitica
      from public.contabil_plano_contas where id=p_conta_contabil_id and ativo=true;
    if v_conta_empresa is null or (not public.is_master() and v_conta_empresa<>v_empresa) then
      raise exception 'Conta contábil não encontrada para a empresa atual.';
    end if;
    if v_analitica is not true then raise exception 'Somente contas analíticas podem receber vínculos.'; end if;
  end if;
  v_sql := format('update public.%I set conta_contabil_id=$1 where id=$2 and empresa_id=$3',p_tabela);
  execute v_sql using p_conta_contabil_id,p_registro_id,v_empresa;
  if not found then raise exception 'Registro financeiro não encontrado para a empresa atual.'; end if;
end;
$$;

-- Valida exercício, período e imutabilidade de lançamentos finalizados.
create or replace function public.validar_lancamento_contabil()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_empresa uuid; v_inicio date; v_fim date; v_status text;
begin
  if tg_op='UPDATE' then
    if old.status='contabilizado' and to_jsonb(new) is distinct from to_jsonb(old) then
      raise exception 'Lançamento contabilizado não pode ser alterado.';
    end if;
    if old.status='cancelado' and to_jsonb(new) is distinct from to_jsonb(old) then
      raise exception 'Lançamento cancelado não pode ser alterado.';
    end if;
  end if;
  if new.exercicio_id is null then raise exception 'O exercício contábil é obrigatório.'; end if;
  select empresa_id,data_inicio,data_fim,status into v_empresa,v_inicio,v_fim,v_status
    from public.contabil_exercicios where id=new.exercicio_id;
  if v_empresa is null or v_empresa<>new.empresa_id then raise exception 'O exercício deve pertencer à mesma empresa.'; end if;
  if v_status<>'aberto' then raise exception 'O exercício contábil está fechado.'; end if;
  if new.data<v_inicio or new.data>v_fim then raise exception 'A data do lançamento está fora do período do exercício.'; end if;
  new.referencia:=to_char(new.data,'YYYY-MM');
  new.updated_at:=now();
  return new;
end;
$$;

drop trigger if exists trg_validar_lancamento_contabil on public.contabil_lancamentos;
create trigger trg_validar_lancamento_contabil
before insert or update on public.contabil_lancamentos
for each row execute function public.validar_lancamento_contabil();

create or replace function public.proteger_partida_contabil_finalizada()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_status text;
begin
  select status into v_status from public.contabil_lancamentos where id=coalesce(new.lancamento_id,old.lancamento_id);
  if v_status in ('contabilizado','cancelado') then
    raise exception 'Partidas de lançamento finalizado não podem ser alteradas.';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists trg_proteger_partida_finalizada on public.contabil_partidas;
create trigger trg_proteger_partida_finalizada
before insert or update or delete on public.contabil_partidas
for each row execute function public.proteger_partida_contabil_finalizada();

-- Criação atômica: cabeçalho e partidas são gravados ou revertidos juntos.
create or replace function public.criar_lancamento_contabil_simples(
  p_exercicio_id uuid,
  p_data date,
  p_historico text,
  p_documento text,
  p_conta_debito_id uuid,
  p_conta_credito_id uuid,
  p_valor numeric,
  p_observacoes text default null,
  p_contabilizar boolean default false
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare v_empresa uuid:=public.current_empresa_id(); v_id uuid;
begin
  if not (public.is_master() or (public.is_ativo() and public.current_role() in ('admin','tesoureiro'))) then
    raise exception 'Sem permissão para criar lançamento contábil.';
  end if;
  if v_empresa is null then raise exception 'Empresa atual não identificada.'; end if;
  if coalesce(trim(p_historico),'')='' then raise exception 'Informe o histórico.'; end if;
  if p_valor is null or p_valor<=0 then raise exception 'O valor deve ser maior que zero.'; end if;
  if p_conta_debito_id=p_conta_credito_id then raise exception 'Débito e crédito devem usar contas diferentes.'; end if;

  insert into public.contabil_lancamentos
    (empresa_id,exercicio_id,data,referencia,historico,documento,origem_tipo,status,observacoes,created_by)
  values
    (v_empresa,p_exercicio_id,p_data,to_char(p_data,'YYYY-MM'),trim(p_historico),nullif(trim(p_documento),''),'manual','rascunho',nullif(trim(p_observacoes),''),auth.uid())
  returning id into v_id;

  insert into public.contabil_partidas
    (empresa_id,lancamento_id,conta_contabil_id,tipo,valor,ordem,created_by)
  values
    (v_empresa,v_id,p_conta_debito_id,'debito',round(p_valor,2),1,auth.uid()),
    (v_empresa,v_id,p_conta_credito_id,'credito',round(p_valor,2),2,auth.uid());

  if p_contabilizar then perform public.contabilizar_lancamento(v_id); end if;
  return v_id;
end;
$$;

grant execute on function public.salvar_vinculo_contabil(text,uuid,uuid) to authenticated;
grant execute on function public.criar_lancamento_contabil_simples(uuid,date,text,text,uuid,uuid,numeric,text,boolean) to authenticated;

commit;
