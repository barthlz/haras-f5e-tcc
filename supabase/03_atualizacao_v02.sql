-- Haras F5E v0.2 - executar UMA vez no projeto SUPABASE JÁ EXISTENTE.
-- Preserva todos os clientes, animais, pagamentos e outros dados cadastrados.
-- É uma ALTERAÇÃO; NÃO execute novamente a estrutura 01 no banco já em uso.

begin;

alter table public.clients
  add column if not exists client_number text;

alter table public.animals
  add column if not exists species text;

-- Regras para registros criados/alterados a partir desta versão.
-- O cliente pode ficar sem número; preenchido, deve conter apenas dígitos.
do $migration$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.clients'::regclass
      and conname = 'haras_clients_number_format'
  ) then
    alter table public.clients
      add constraint haras_clients_number_format
      check (client_number is null or client_number ~ '^[0-9]+$');
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.animals'::regclass
      and conname = 'haras_animals_species_options'
  ) then
    alter table public.animals
      add constraint haras_animals_species_options
      check (species is null or species in (
        'Equino', 'Bovino', 'Asinino', 'Muar', 'Ovino', 'Caprino', 'Suíno', 'Outro'
      ));
  end if;
end;
$migration$;

create unique index if not exists haras_clients_number_unique
  on public.clients (client_number)
  where client_number is not null;

commit;

-- Conferir no Table Editor: public.clients.client_number e public.animals.species.
-- Não é necessário recriar políticas RLS, aprovações nem tabelas.
