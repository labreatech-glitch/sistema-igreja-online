-- V67 - Corrige a validacao de caixa nas origens da prestacao de contas.
-- prestacao_fontes_slide.origem_id e text para aceitar diferentes tipos de
-- origem, enquanto tipos_caixa.id e uuid. A conversao deve ser explicita.

begin;

create or replace function public.validar_caixa_ativo_origem_prestacao()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caixa_id uuid;
  caixa_ativo boolean;
begin
  if new.tipo_origem <> 'caixa' then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and new.origem_id is not distinct from old.origem_id
     and new.tipo_origem is not distinct from old.tipo_origem then
    return new;
  end if;

  begin
    caixa_id := trim(new.origem_id)::uuid;
  exception
    when invalid_text_representation then
      raise exception 'Identificador de caixa inválido na origem do slide.' using errcode = '22P02';
  end;

  select tc.ativo
    into caixa_ativo
    from public.tipos_caixa tc
   where tc.id = caixa_id
     and tc.empresa_id = new.empresa_id;

  if not found then
    raise exception 'Caixa não encontrado para esta igreja.' using errcode = '23503';
  end if;

  if caixa_ativo is false then
    raise exception 'Caixa inativo não pode ser incluído como nova origem do slide.' using errcode = '23514';
  end if;

  return new;
end;
$$;

notify pgrst, 'reload schema';
commit;
