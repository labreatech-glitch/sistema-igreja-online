-- =========================================================
-- V65 — Pré-cadastro, selo externo e estado de conservação
-- Migração aditiva e compatível com todos os bens existentes.
-- =========================================================

begin;

alter table public.patrimonio
  add column if not exists codigo_etiqueta text,
  add column if not exists estado_conservacao text;

alter table public.patrimonio
  drop constraint if exists patrimonio_codigo_etiqueta_check;
alter table public.patrimonio
  add constraint patrimonio_codigo_etiqueta_check
  check (
    codigo_etiqueta is null
    or (
      nullif(btrim(codigo_etiqueta), '') is not null
      and char_length(btrim(codigo_etiqueta)) <= 120
    )
  );

alter table public.patrimonio
  drop constraint if exists patrimonio_estado_conservacao_check;
alter table public.patrimonio
  add constraint patrimonio_estado_conservacao_check
  check (
    estado_conservacao is null
    or estado_conservacao in ('novo','bom','regular','ruim','inservivel')
  );

create unique index if not exists patrimonio_empresa_codigo_etiqueta_uidx
  on public.patrimonio (empresa_id, upper(btrim(codigo_etiqueta)))
  where nullif(btrim(codigo_etiqueta), '') is not null;

comment on column public.patrimonio.codigo_etiqueta is
  'Código externo já impresso no selo/etiqueta física. Único por igreja.';
comment on column public.patrimonio.estado_conservacao is
  'Estado observado no levantamento: novo, bom, regular, ruim ou inservível.';

notify pgrst, 'reload schema';
commit;
