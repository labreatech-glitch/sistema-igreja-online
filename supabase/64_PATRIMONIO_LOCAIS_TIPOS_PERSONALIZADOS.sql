-- =========================================================
-- V64 — Tipos personalizados para locais do patrimônio
-- Migração não destrutiva: preserva todos os locais e tipos atuais.
-- =========================================================

begin;

alter table public.patrimonio_locais
  drop constraint if exists patrimonio_locais_tipo_check;

alter table public.patrimonio_locais
  add constraint patrimonio_locais_tipo_check
  check (
    nullif(btrim(tipo), '') is not null
    and char_length(btrim(tipo)) <= 80
  );

comment on column public.patrimonio_locais.tipo is
  'Tipo padrão ou personalizado do local patrimonial, limitado a 80 caracteres.';

notify pgrst, 'reload schema';
commit;
