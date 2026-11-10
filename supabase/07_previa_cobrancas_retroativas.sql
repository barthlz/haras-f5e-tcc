-- HARAS F5E v0.4.2 | PRÉVIA DE COBRANÇAS PENDENTES
-- SOMENTE SELECT: execute ANTES de instalar a migração, não altera dados.
-- Valores estimados com os preços e serviços ATUAIS (podem ter mudado).
with settings as (
 select billing_start_month from public.stay_billing_settings where singleton=true
), prices as (
 select coalesce(max(amount) filter(where service='hospedagem'),1000) as hospedagem,
        coalesce(max(amount) filter(where service='reproducao'),1200) as reproducao,
        coalesce(max(amount) filter(where service='treinamento'),1400) as treinamento
 from public.stay_prices
), candidates as (
 select c.name as cliente,a.name as animal,m::date as mes,
        case when a.billing_category <> 'Padrão' then 0::numeric
             when a.lodging_enabled or a.breeding_enabled or a.training_enabled then
                (case when a.lodging_enabled then p.hospedagem else 0 end) +
                (case when a.breeding_enabled then p.reproducao else 0 end) +
                (case when a.training_enabled then p.treinamento else 0 end)
             else a.base_monthly_amount end as valor
 from public.animals a
 join public.clients c on c.id=a.owner_client_id
 cross join settings s cross join prices p
 cross join lateral generate_series(
    coalesce(date_trunc('month',a.arrival_date)::date,s.billing_start_month),
    least(date_trunc('month',current_date)::date,
       coalesce(date_trunc('month',a.departure_date)::date,date_trunc('month',current_date)::date)),
    interval '1 month') as m
 left join public.stay_charges sc on sc.animal_id=a.id and sc.reference_month=m::date
 where sc.id is null
)
select cliente,animal,count(*) as meses_pendentes,
       min(mes) as primeiro_mes,max(mes) as ultimo_mes,
       sum(valor) as total_estimado_a_acrescentar
from candidates
group by cliente,animal order by cliente,animal;
