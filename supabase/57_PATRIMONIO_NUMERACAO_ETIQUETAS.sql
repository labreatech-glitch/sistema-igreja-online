begin;

create extension if not exists pgcrypto;

alter table public.empresas
  add column if not exists patrimonio_prefixo text;

alter table public.patrimonio
  add column if not exists sequencial integer,
  add column if not exists prefixo text,
  add column if not exists marca text,
  add column if not exists modelo text,
  add column if not exists numero_serie text,
  add column if not exists fornecedor text,
  add column if not exists nota_fiscal text,
  add column if not exists responsavel text,
  add column if not exists garantia_ate date,
  add column if not exists foto_url text,
  add column if not exists documento_url text,
  add column if not exists data_baixa date,
  add column if not exists motivo_baixa text;

alter table public.patrimonio drop constraint if exists patrimonio_status_check;
alter table public.patrimonio add constraint patrimonio_status_check
  check (status in ('ativo','manutencao','emprestado','cedido','extraviado','baixado'));

create table if not exists public.patrimonio_contadores (
  empresa_id uuid primary key references public.empresas(id) on delete cascade,
  ultimo_numero integer not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists public.patrimonio_historico (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  patrimonio_id uuid not null references public.patrimonio(id) on delete cascade,
  evento text not null,
  detalhes text,
  dados_anteriores jsonb,
  dados_novos jsonb,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create or replace function public.patrimonio_gerar_prefixo(p_nome text)
returns text
language plpgsql
immutable
as $$
declare
  palavra text;
  resultado text := '';
  normalizado text;
begin
  normalizado := upper(translate(coalesce(p_nome,''),
    'ÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇÑáàãâäéèêëíìîïóòõôöúùûüçñ',
    'AAAAAEEEEIIIIOOOOOUUUUCNaaaaaeeeeiiiiooooouuuucn'));
  normalizado := regexp_replace(normalizado, '[^A-Z0-9 ]', ' ', 'g');
  foreach palavra in array regexp_split_to_array(normalizado, '\s+') loop
    if palavra <> '' and palavra not in ('DE','DA','DO','DAS','DOS','E') then
      resultado := resultado || substr(palavra,1,1);
    end if;
  end loop;
  return left(coalesce(nullif(resultado,''),'PAT'),8);
end;
$$;

create or replace function public.patrimonio_numero_automatico()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nome text;
  v_prefixo text;
  v_numero integer;
begin
  if tg_op = 'UPDATE' then
    new.numero_patrimonio := old.numero_patrimonio;
    new.sequencial := old.sequencial;
    new.prefixo := old.prefixo;
    return new;
  end if;

  select coalesce(nullif(patrimonio_prefixo,''), public.patrimonio_gerar_prefixo(coalesce(nullif(nome,''), nome_fantasia)))
    into v_prefixo
    from public.empresas where id = new.empresa_id;

  insert into public.patrimonio_contadores(empresa_id, ultimo_numero)
  values (new.empresa_id, 1)
  on conflict (empresa_id) do update
    set ultimo_numero = public.patrimonio_contadores.ultimo_numero + 1,
        updated_at = now()
  returning ultimo_numero into v_numero;

  new.prefixo := v_prefixo;
  new.sequencial := v_numero;
  new.numero_patrimonio := v_prefixo || '-' || lpad(v_numero::text,4,'0');
  return new;
end;
$$;

-- Numera registros antigos ainda sem padrão.
with ordenados as (
  select id, empresa_id,
         row_number() over(partition by empresa_id order by created_at, id)::integer as seq
  from public.patrimonio
  where sequencial is null or numero_patrimonio is null or numero_patrimonio = ''
), dados as (
  select o.id, o.empresa_id, o.seq,
         coalesce(nullif(e.patrimonio_prefixo,''), public.patrimonio_gerar_prefixo(coalesce(nullif(e.nome,''),e.nome_fantasia))) as pref
  from ordenados o join public.empresas e on e.id=o.empresa_id
)
update public.patrimonio p
set sequencial=d.seq, prefixo=d.pref, numero_patrimonio=d.pref||'-'||lpad(d.seq::text,4,'0')
from dados d where p.id=d.id;

insert into public.patrimonio_contadores(empresa_id,ultimo_numero)
select empresa_id,max(coalesce(sequencial,0)) from public.patrimonio group by empresa_id
on conflict(empresa_id) do update set ultimo_numero=greatest(public.patrimonio_contadores.ultimo_numero,excluded.ultimo_numero),updated_at=now();

drop trigger if exists trg_patrimonio_numero_automatico on public.patrimonio;
create trigger trg_patrimonio_numero_automatico
before insert or update of numero_patrimonio, sequencial, prefixo on public.patrimonio
for each row execute function public.patrimonio_numero_automatico();

create unique index if not exists patrimonio_empresa_sequencial_uidx on public.patrimonio(empresa_id,sequencial);
create unique index if not exists patrimonio_empresa_numero_uidx on public.patrimonio(empresa_id,numero_patrimonio);

create or replace function public.patrimonio_registrar_historico()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_evento text;
  v_detalhes text;
begin
  if tg_op='INSERT' then
    v_evento := 'Cadastro';
    v_detalhes := 'Bem cadastrado com o número '||new.numero_patrimonio;
    insert into public.patrimonio_historico(empresa_id,patrimonio_id,evento,detalhes,dados_novos,created_by)
    values(new.empresa_id,new.id,v_evento,v_detalhes,to_jsonb(new),new.created_by);
    return new;
  elsif tg_op='UPDATE' then
    if old.status is distinct from new.status then
      v_evento := case when new.status='baixado' then 'Baixa' else 'Alteração de status' end;
      v_detalhes := coalesce(old.status,'—')||' → '||coalesce(new.status,'—')||case when new.motivo_baixa is not null then '. Motivo: '||new.motivo_baixa else '' end;
    elsif old.local_id is distinct from new.local_id or old.localizacao is distinct from new.localizacao then
      v_evento := 'Transferência de local'; v_detalhes := 'Localização do bem alterada.';
    elsif old.responsavel is distinct from new.responsavel then
      v_evento := 'Mudança de responsável'; v_detalhes := coalesce(old.responsavel,'—')||' → '||coalesce(new.responsavel,'—');
    else
      v_evento := 'Atualização'; v_detalhes := 'Dados do patrimônio atualizados.';
    end if;
    insert into public.patrimonio_historico(empresa_id,patrimonio_id,evento,detalhes,dados_anteriores,dados_novos,created_by)
    values(new.empresa_id,new.id,v_evento,v_detalhes,to_jsonb(old),to_jsonb(new),auth.uid());
    return new;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_patrimonio_historico on public.patrimonio;
create trigger trg_patrimonio_historico after insert or update on public.patrimonio
for each row execute function public.patrimonio_registrar_historico();

alter table public.patrimonio_contadores enable row level security;
alter table public.patrimonio_historico enable row level security;

drop policy if exists patrimonio_contadores_select on public.patrimonio_contadores;
create policy patrimonio_contadores_select on public.patrimonio_contadores for select using (empresa_id=public.current_empresa_id() or public.is_master());
drop policy if exists patrimonio_historico_select on public.patrimonio_historico;
create policy patrimonio_historico_select on public.patrimonio_historico for select using (empresa_id=public.current_empresa_id() or public.is_master());

commit;
