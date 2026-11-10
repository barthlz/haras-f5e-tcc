-- HARAS F5E v0.4.2 | MENSALIDADES ACUMULADAS
-- Execute SOMENTE após a v0.4, um backup e a conferência da prévia.
-- Não apaga clientes, animais, pagamentos nem cobranças existentes.
-- Na próxima abertura da aba, gera mensalidades retroativas desde o mês
-- de ENTRADA de cada animal com proprietário, se faltarem competências.
-- Animais sem entrada informada continuam a cobrar do mês da instalação.
begin;

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
 -- Conta desde o mês de entrada, mesmo antes da instalação da v0.4.
 -- Sem entrada, mantém o mês da instalação como início.
 if p_month > v_current
    or (a.arrival_date is null and p_month < v_start)
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

create or replace function public.haras_sync_stay_charges()
returns void language plpgsql security definer set search_path = '' as $$
declare
 a record;
 m date;
 v_start date;
 v_first date;
 v_last date;
 v_current date := date_trunc('month',current_date)::date;
begin
 if not public.can_haras('recebimentos_estadia','view') then
  raise exception 'Sem acesso a recebimentos de estadia.';
 end if;
 perform pg_catalog.pg_advisory_xact_lock(405, 2026);
 select billing_start_month into v_start from public.stay_billing_settings where singleton=true;
 if v_start is null then
  raise exception 'Configuração da cobrança não encontrada.';
 end if;
 for a in select id,arrival_date,departure_date from public.animals
          where owner_client_id is not null loop
   v_first := coalesce(date_trunc('month',a.arrival_date)::date,v_start);
   v_last := least(v_current,coalesce(date_trunc('month',a.departure_date)::date,v_current));
   if v_first <= v_last then
     for m in select generate_series(v_first,v_last,interval '1 month')::date loop
       perform public.haras_write_stay_charge(a.id,m);
     end loop;
   end if;
 end loop;
end; $$;
revoke all on function public.haras_sync_stay_charges() from public,anon;
grant execute on function public.haras_sync_stay_charges() to authenticated;

create or replace function public.haras_client_stay_balance(p_client uuid)
returns table (total_charged numeric,total_paid numeric,balance numeric)
language plpgsql stable security definer set search_path = '' as $$
declare v_start date; v_earliest date;
begin
 if not public.can_haras('recebimentos_estadia','view') then
  raise exception 'Sem acesso a recebimentos de estadia.';
 end if;
 select billing_start_month into v_start from public.stay_billing_settings where singleton=true;
 select min(sc.reference_month) into v_earliest
   from public.stay_charges sc where sc.client_id=p_client;
 -- Evita usar pagamentos de períodos anteriores ao primeiro mês cobrado.
 -- Respeita o mês de referência, quando houver; caso contrário usa a data.
 v_start := least(v_start,coalesce(v_earliest,v_start));
 return query
 with charged as (
   select coalesce(sum(sc.amount),0)::numeric as total
   from public.stay_charges sc where sc.client_id=p_client
 ), paid as (
   select coalesce(sum(p.amount),0)::numeric as total
   from public.payments p
   where p.client_id=p_client
     and coalesce(p.reference_month,p.payment_date)>=v_start
 )
 select c.total,p.total,c.total-p.total from charged c cross join paid p;
end; $$;
revoke all on function public.haras_client_stay_balance(uuid) from public,anon;
grant execute on function public.haras_client_stay_balance(uuid) to authenticated;

-- Detalhamento mensal das mensalidades cobradas (sem pagamentos).
create or replace function public.haras_client_stay_monthly_summary(p_client uuid)
returns table (reference_month date,total_charged numeric)
language plpgsql stable security definer set search_path = '' as $$
begin
 if not public.can_haras('recebimentos_estadia','view') then
  raise exception 'Sem acesso a recebimentos de estadia.';
 end if;
 return query
 select sc.reference_month, sum(sc.amount)::numeric
 from public.stay_charges sc where sc.client_id=p_client
 group by sc.reference_month order by sc.reference_month desc;
end; $$;
revoke all on function public.haras_client_stay_monthly_summary(uuid) from public,anon;
grant execute on function public.haras_client_stay_monthly_summary(uuid) to authenticated;

commit;
notify pgrst, 'reload schema';
