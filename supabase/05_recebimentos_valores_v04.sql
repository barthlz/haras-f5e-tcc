-- HARAS F5E v0.4 | RECEBIMENTOS DE ESTADIA E VALORES
-- Execute no SQL Editor SOMENTE APOS a v0.3 e apos um BACKUP.
-- MIGRACAO ADITIVA: nao tem DROP TABLE nem DELETE dos cadastros existentes.
-- Cobranças começam no primeiro dia do mês da instalação; nada é cobrado retroativamente.
begin;

-- Amplia a lista permitida de modulos para as novas abas.
alter table public.role_permissions drop constraint if exists role_permissions_module_check;
alter table public.role_permissions add constraint role_permissions_module_check
  check (module in ('resumo','clientes','despesas','funcionarios','animais',
    'pagamentos','hospedagem','treinamento','reproducao','exames',
    'recebimentos_estadia','valores'));

insert into public.role_permissions(role,module,can_view,can_create,can_edit,can_delete)
values
 ('administrador','recebimentos_estadia',true,true,true,true),
 ('administrador','valores',true,true,true,false),
 ('gerente','recebimentos_estadia',true,true,true,true),
 ('gerente','valores',true,true,true,false),
 ('financeiro','recebimentos_estadia',true,true,true,false),
 ('financeiro','valores',true,false,false,false)
on conflict(role,module) do update set can_view=excluded.can_view,
 can_create=excluded.can_create,can_edit=excluded.can_edit,can_delete=excluded.can_delete;

create table if not exists public.stay_prices (
  service text primary key check (service in ('hospedagem','reproducao','treinamento')),
  amount numeric(12,2) not null check (amount >= 0),
  updated_at timestamptz not null default now()
);
insert into public.stay_prices(service,amount) values
 ('hospedagem',1000),('reproducao',1200),('treinamento',1400)
on conflict(service) do nothing;

create table if not exists public.stay_billing_settings (
  singleton boolean primary key default true check(singleton),
  billing_start_month date not null
);
insert into public.stay_billing_settings(singleton,billing_start_month)
 values (true,date_trunc('month',current_date)::date)
on conflict(singleton) do nothing;

alter table public.animals
 add column if not exists billing_category text not null default 'Padrão';
alter table public.animals
 add column if not exists base_monthly_amount numeric(12,2) not null default 1400;
-- CHECKs por nome, sem duplicar nas execucoes seguintes.
do $$ begin
 if not exists (select 1 from pg_constraint where conname = 'haras_animal_billing_category_check') then
  alter table public.animals add constraint haras_animal_billing_category_check
  check (billing_category in ('Padrão','F5E Treinamento','F5E Hospedagem','F5E Reprodução'));
 end if;
 if not exists (select 1 from pg_constraint where conname = 'haras_animal_base_amount_check') then
  alter table public.animals add constraint haras_animal_base_amount_check check(base_monthly_amount >= 0);
 end if;
end $$;

-- Distingue recebimentos de estadia dos pagamentos tradicionais, sem exclui-los.
alter table public.payments
 add column if not exists payment_kind text not null default 'geral';
do $$ begin
 if not exists (select 1 from pg_constraint where conname = 'haras_payment_kind_check') then
  alter table public.payments add constraint haras_payment_kind_check
  check (payment_kind in ('geral','estadia'));
 end if;
end $$;

-- Livro de mensalidades. Valores, meses e proprietarios ja faturados ficam
-- registrados mesmo se o animal/cliente for excluido depois.
create table if not exists public.stay_charges (
 id uuid primary key default gen_random_uuid(),
 animal_id uuid references public.animals(id) on delete set null,
 client_id uuid references public.clients(id) on delete set null,
 animal_name_snapshot text not null,
 client_name_snapshot text,
 reference_month date not null check (extract(day from reference_month) = 1),
 amount numeric(12,2) not null check (amount >= 0),
 summary text not null,
 created_at timestamptz not null default now(),
 unique(animal_id,reference_month)
);
create index if not exists idx_haras_stay_charges_client on public.stay_charges(client_id,reference_month);
create index if not exists idx_haras_stay_charges_month on public.stay_charges(reference_month);

alter table public.stay_prices enable row level security;
drop policy if exists haras_read on public.stay_prices;
create policy haras_read on public.stay_prices for select to authenticated
 using ((select public.can_haras('valores','view')));
drop policy if exists haras_edit on public.stay_prices;
create policy haras_edit on public.stay_prices for update to authenticated
 using ((select public.can_haras('valores','edit')))
 with check ((select public.can_haras('valores','edit')));
revoke all on public.stay_prices from anon;
grant select,update on public.stay_prices to authenticated;

alter table public.stay_charges enable row level security;
drop policy if exists haras_read on public.stay_charges;
create policy haras_read on public.stay_charges for select to authenticated
 using ((select public.can_haras('recebimentos_estadia','view')));
revoke all on public.stay_charges from anon,authenticated;
grant select on public.stay_charges to authenticated;

alter table public.stay_billing_settings enable row level security;
drop policy if exists haras_read on public.stay_billing_settings;
create policy haras_read on public.stay_billing_settings for select to authenticated
 using ((select public.can_haras('recebimentos_estadia','view')));
revoke all on public.stay_billing_settings from anon,authenticated;
grant select on public.stay_billing_settings to authenticated;

-- So gerente ou administrador podem conceder categoria F5E sem custo ou
-- alterar o valor-base dos animais; treinador continua podendo marcar servicos.
create or replace function public.haras_protect_animal_billing()
returns trigger language plpgsql set search_path = '' as $$
begin
 if tg_op = 'INSERT' then
   if (new.billing_category <> 'Padrão' or new.base_monthly_amount <> 1400)
     and not public.can_haras('valores','edit') then
     raise exception 'Sem permissão para alterar categoria F5E ou valor padrão.';
   end if;
 elsif tg_op = 'UPDATE' then
   if (new.billing_category is distinct from old.billing_category or
       new.base_monthly_amount is distinct from old.base_monthly_amount)
      and not public.can_haras('valores','edit') then
     raise exception 'Sem permissão para alterar categoria F5E ou valor padrão.';
   end if;
 end if;
 return new;
end; $$;
drop trigger if exists trg_haras_protect_animal_billing on public.animals;
create trigger trg_haras_protect_animal_billing before insert or update on public.animals
 for each row execute function public.haras_protect_animal_billing();

-- Funcao interna: aplica as tarifas vigentes, uma vez por animal/mes.
-- Se nao houver servico marcado, aplica R$ 1.400 (valor padrao do animal).
-- Se houver 1+ servicos, SOMA SOMENTE os selecionados.
-- Categoria F5E sempre = R$ 0.
create or replace function public.haras_write_stay_charge(p_animal uuid,p_month date)
returns void language plpgsql security definer set search_path = '' as $$
declare
 a public.animals%rowtype;
 v_start date;
 v_total numeric(12,2);
 v_services text;
 v_lodge numeric(12,2);
 v_breed numeric(12,2);
 v_train numeric(12,2);
 v_client text;
 v_current date := date_trunc('month',current_date)::date;
begin
 select * into a from public.animals where id=p_animal;
 if not found then return; end if;
 select billing_start_month into v_start from public.stay_billing_settings where singleton=true;
 -- Nunca apague cobranças emitidas se um cliente for excluído: a FK apenas
 -- desvincula o cliente. Isso preserva inclusive a competência atual.
 if a.owner_client_id is null then return; end if;
 if p_month < v_start or p_month > v_current
    or (a.arrival_date is not null and date_trunc('month',a.arrival_date)::date > p_month)
    or (a.departure_date is not null and date_trunc('month',a.departure_date)::date < p_month) then
   -- Um ajuste de datas de entrada/saida pode cancelar a mensalidade atual.
   -- Mensalidades de meses anteriores permanecem intactas.
   if p_month = v_current then
    delete from public.stay_charges where animal_id=p_animal and reference_month=p_month;
   end if;
   return;
 end if;
 select name into v_client from public.clients where id=a.owner_client_id;
 select coalesce(max(amount) filter (where service='hospedagem'),1000),
        coalesce(max(amount) filter (where service='reproducao'),1200),
        coalesce(max(amount) filter (where service='treinamento'),1400)
 into v_lodge,v_breed,v_train from public.stay_prices;
 if a.billing_category <> 'Padrão' then
   v_total:=0; v_services:=a.billing_category || ' (isento)';
 elsif a.lodging_enabled or a.breeding_enabled or a.training_enabled then
   v_total:=(case when a.lodging_enabled then v_lodge else 0 end)
        +(case when a.breeding_enabled then v_breed else 0 end)
        +(case when a.training_enabled then v_train else 0 end);
   v_services:=concat_ws(' + ',case when a.lodging_enabled then 'Hospedagem' end,
     case when a.breeding_enabled then 'Reprodução' end,
     case when a.training_enabled then 'Treinamento' end);
 else
   v_total:=a.base_monthly_amount; v_services:='Padrão do animal';
 end if;
 insert into public.stay_charges
   (animal_id,client_id,animal_name_snapshot,client_name_snapshot,reference_month,amount,summary)
 values(p_animal,a.owner_client_id,a.name,v_client,p_month,v_total,v_services)
 on conflict(animal_id,reference_month) do update
 set client_id=excluded.client_id,animal_name_snapshot=excluded.animal_name_snapshot,
     client_name_snapshot=excluded.client_name_snapshot,amount=excluded.amount,
     summary=excluded.summary
 -- Recalcular apenas o mes vigente. Meses fechados nunca mudam retroativamente.
 where stay_charges.reference_month=v_current;
end; $$;
revoke all on function public.haras_write_stay_charge(uuid,date) from public,anon,authenticated;

create or replace function public.haras_animal_stay_changed()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
 perform public.haras_write_stay_charge(new.id,date_trunc('month',current_date)::date);
 return new;
end; $$;
drop trigger if exists trg_haras_animal_stay_changed on public.animals;
create trigger trg_haras_animal_stay_changed
 after insert or update of owner_client_id,name,arrival_date,departure_date,
    lodging_enabled,breeding_enabled,training_enabled,billing_category,base_monthly_amount
 on public.animals for each row execute function public.haras_animal_stay_changed();

-- Replicar tarifas novas apenas no mes atual.
create or replace function public.haras_price_stay_changed()
returns trigger language plpgsql security definer set search_path = '' as $$
declare aid uuid;
begin
 for aid in select id from public.animals loop
   perform public.haras_write_stay_charge(aid,date_trunc('month',current_date)::date);
 end loop;
 return new;
end; $$;
drop trigger if exists trg_haras_price_stay_changed on public.stay_prices;
create trigger trg_haras_price_stay_changed after update of amount on public.stay_prices
 for each row execute function public.haras_price_stay_changed();

-- Ao abrir a aba, gerar mensalidades ainda nao lancadas desde a migracao.
-- Os precos existentes sao "fotografados" quando o mes e criado.
create or replace function public.haras_sync_stay_charges()
returns void language plpgsql security definer set search_path = '' as $$
declare a record; m date; v_start date; v_current date := date_trunc('month',current_date)::date;
begin
 if not public.can_haras('recebimentos_estadia','view') then
  raise exception 'Sem acesso a recebimentos de estadia.';
 end if;
 perform pg_catalog.pg_advisory_xact_lock(405, 2026);
 select billing_start_month into v_start from public.stay_billing_settings where singleton=true;
 for a in select id,arrival_date,departure_date from public.animals where owner_client_id is not null loop
   for m in select generate_series(
     greatest(v_start,coalesce(date_trunc('month',a.arrival_date)::date,v_start)),
     least(v_current,coalesce(date_trunc('month',a.departure_date)::date,v_current)),
     interval '1 month')::date loop
     perform public.haras_write_stay_charge(a.id,m);
   end loop;
 end loop;
end; $$;
revoke all on function public.haras_sync_stay_charges() from public,anon;
grant execute on function public.haras_sync_stay_charges() to authenticated;

-- Saldo por cliente: mensalidades desde a v0.4 menos pagamentos desde a v0.4.
-- Pagamentos anteriores NAO sao apagados nem usados para gerar credito indevido.
create or replace function public.haras_client_stay_balance(p_client uuid)
returns table (total_charged numeric,total_paid numeric,balance numeric)
language plpgsql stable security definer set search_path = '' as $$
declare v_start date;
begin
 if not public.can_haras('recebimentos_estadia','view') then
  raise exception 'Sem acesso a recebimentos de estadia.';
 end if;
 select billing_start_month into v_start from public.stay_billing_settings where singleton=true;
 return query
 with charged as (
   select coalesce(sum(sc.amount),0)::numeric as total from public.stay_charges sc
   where sc.client_id=p_client and sc.reference_month>=v_start
 ), paid as (
   select coalesce(sum(p.amount),0)::numeric as total from public.payments p
   where p.client_id=p_client and p.payment_date>=v_start
 )
 select c.total, p.total, c.total-p.total from charged c cross join paid p;
end; $$;
revoke all on function public.haras_client_stay_balance(uuid) from public,anon;
grant execute on function public.haras_client_stay_balance(uuid) to authenticated;

commit;
notify pgrst, 'reload schema';
