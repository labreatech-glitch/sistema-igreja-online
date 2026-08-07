-- Proteção de integridade para grupos gerenciais de despesas.
-- Permite editar e inativar normalmente, mas bloqueia exclusão quando houver vínculos.

create or replace function public.proteger_exclusao_grupo_gerencial_despesa()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  qtd_categorias bigint;
  qtd_despesas bigint;
begin
  select count(*) into qtd_categorias
  from public.categorias_despesas
  where grupo_gerencial_id = old.id
    and empresa_id = old.empresa_id;

  select count(*) into qtd_despesas
  from public.despesas
  where grupo_gerencial_id = old.id
    and empresa_id = old.empresa_id;

  if qtd_categorias > 0 or qtd_despesas > 0 then
    raise exception 'Não é possível excluir o grupo gerencial "%": existem % categoria(s) e % despesa(s) vinculada(s). Inative o grupo ou transfira os vínculos antes da exclusão.',
      old.nome, qtd_categorias, qtd_despesas
      using errcode = '23503';
  end if;

  return old;
end;
$$;

drop trigger if exists trg_proteger_exclusao_grupo_gerencial on public.grupos_gerenciais_despesas;
create trigger trg_proteger_exclusao_grupo_gerencial
before delete on public.grupos_gerenciais_despesas
for each row execute function public.proteger_exclusao_grupo_gerencial_despesa();

comment on function public.proteger_exclusao_grupo_gerencial_despesa() is
'Impede excluir grupo gerencial com categorias ou despesas vinculadas; a inativação continua permitida.';
