-- HARAS F5E | v0.3 | exclusão confirmada de registros com vínculos.
-- EXECUTAR SOMENTE no Supabase do Haras F5E, DEPOIS de criar um backup.
-- Este script ALTERA regras de chave estrangeira; não apaga dados ao executar.
-- As exclusões feitas posteriormente no aplicativo são definitivas.
-- NÃO execute o script 01 de criação novamente em um banco já utilizado.

begin;

-- Nunca excluir pagamentos automaticamente ao apagar clientes:
-- o cliente pode ser apagado e o pagamento continua registrado.
-- Guardamos o nome histórico do cliente para identificação desses pagamentos.
alter table public.payments
  add column if not exists client_name_snapshot text;

update public.payments p
set client_name_snapshot = c.name
from public.clients c
where p.client_id = c.id
  and nullif(btrim(p.client_name_snapshot), '') is null;

create or replace function public.haras_save_payment_client_name()
returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.client_id is not null then
    select c.name into new.client_name_snapshot
    from public.clients c where c.id = new.client_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_haras_payment_client_snapshot on public.payments;
create trigger trg_haras_payment_client_snapshot
  before insert or update of client_id on public.payments
  for each row execute function public.haras_save_payment_client_name();

alter table public.payments alter column client_id drop not null;
alter table public.payments drop constraint if exists payments_client_id_fkey;
alter table public.payments
  add constraint payments_client_id_fkey
  foreign key (client_id) references public.clients(id) on delete set null;

-- Excluir o animal não pode apagar pagamentos: só a ligação na tabela pivô.
alter table public.payment_animals
  drop constraint if exists payment_animals_animal_id_fkey;
alter table public.payment_animals
  add constraint payment_animals_animal_id_fkey
  foreign key (animal_id) references public.animals(id) on delete cascade;

-- Fichas operacionais exigem um animal existente: ao excluir o animal,
-- as fichas dependentes também são excluídas após confirmação no aplicativo.
alter table public.lodgings
  drop constraint if exists lodgings_animal_id_fkey;
alter table public.lodgings
  add constraint lodgings_animal_id_fkey
  foreign key (animal_id) references public.animals(id) on delete cascade;

alter table public.training_sessions
  drop constraint if exists training_sessions_animal_id_fkey;
alter table public.training_sessions
  add constraint training_sessions_animal_id_fkey
  foreign key (animal_id) references public.animals(id) on delete cascade;

alter table public.breeding_records
  drop constraint if exists breeding_records_animal_id_fkey;
alter table public.breeding_records
  add constraint breeding_records_animal_id_fkey
  foreign key (animal_id) references public.animals(id) on delete cascade;

alter table public.embryo_transfers
  drop constraint if exists embryo_transfers_animal_id_fkey;
alter table public.embryo_transfers
  add constraint embryo_transfers_animal_id_fkey
  foreign key (animal_id) references public.animals(id) on delete cascade;

alter table public.animal_exams
  drop constraint if exists animal_exams_animal_id_fkey;
alter table public.animal_exams
  add constraint animal_exams_animal_id_fkey
  foreign key (animal_id) references public.animals(id) on delete cascade;

-- Mantidas as regras existentes:
--   clients -> client_dependents: CASCADE (dependentes apagados)
--   clients -> animals: SET NULL (animais preservados)
--   payments -> payment_animals: CASCADE (apenas ligações apagadas)
--   breeding_records -> embryo_transfers: SET NULL (receptoras preservadas)
-- As permissões RLS existentes NÃO são alteradas.

commit;

-- Atualizar o cache da API para reconhecer a nova coluna.
notify pgrst, 'reload schema';
