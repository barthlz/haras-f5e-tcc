-- HARAS F5E v0.4.4 | PRIMEIRA MENSALIDADE SOMENTE NO MES SEGUINTE
-- Execute SOMENTE depois da v0.4.3, e apos backup e conferencia da previa.
-- Muda a regra de geracao: o MES DE ENTRADA nunca sera cobrado.
-- Primeira competencia: mes seguinte, vencimento em 10/MM/AAAA.
-- Registros antigos do mes de entrada sao ISENTADOS (amount=0), nao excluidos;
-- o valor anterior e guardado na tabela restrita de auditoria abaixo.
-- NAO altera, apaga ou reatribui recebimentos da tabela public.payments.
-- Saldos podem diminuir, e pagamentos adiantados passam a ser credito.
BEGIN;

CREATE TABLE IF NOT EXISTS public.stay_start_month_adjustments (
  charge_id uuid PRIMARY KEY,
  animal_id uuid,
  client_id uuid,
  animal_name_snapshot text NOT NULL,
  client_name_snapshot text,
  reference_month date NOT NULL,
  original_amount numeric(12,2) NOT NULL,
  original_summary text NOT NULL,
  original_created_at timestamptz NOT NULL,
  adjusted_at timestamptz NOT NULL DEFAULT now(),
  reason text NOT NULL DEFAULT 'Isencao do mes de entrada - v0.4.4'
);
-- Historico acessivel apenas a quem administra o banco pelo SQL Editor.
ALTER TABLE public.stay_start_month_adjustments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.stay_start_month_adjustments FROM PUBLIC, anon, authenticated;

-- Registra antes de zerar. Idempotente: executar duas vezes nao duplica.
INSERT INTO public.stay_start_month_adjustments
  (charge_id,animal_id,client_id,animal_name_snapshot,client_name_snapshot,
   reference_month,original_amount,original_summary,original_created_at)
SELECT sc.id,sc.animal_id,sc.client_id,sc.animal_name_snapshot,
       sc.client_name_snapshot,sc.reference_month,sc.amount,sc.summary,sc.created_at
FROM public.stay_charges sc
JOIN public.animals a ON a.id=sc.animal_id
CROSS JOIN public.stay_billing_settings settings
WHERE settings.singleton=true AND sc.amount > 0
  AND sc.reference_month=coalesce(
    date_trunc('month',a.arrival_date)::date,
    greatest(settings.billing_start_month,
       date_trunc('month',a.created_at at time zone 'America/Sao_Paulo')::date)
  )
ON CONFLICT (charge_id) DO NOTHING;

-- Cobranças emitidas indevidamente para o mês da entrada ficam visíveis como
-- zeradas, para que o histórico permaneça, mas deixem de compor o saldo.
UPDATE public.stay_charges sc
SET amount=0,summary='Mes de entrada (isento - v0.4.4)'
FROM public.animals a, public.stay_billing_settings settings
WHERE a.id=sc.animal_id AND settings.singleton=true AND sc.amount>0
  AND sc.reference_month=coalesce(
    date_trunc('month',a.arrival_date)::date,
    greatest(settings.billing_start_month,
      date_trunc('month',a.created_at at time zone 'America/Sao_Paulo')::date)
  );

-- Funcoes atuais, sem modificar servicos, categorias, valores ou pagamentos.
create or replace function public.haras_write_stay_charge(p_animal uuid,p_month date)
returns void language plpgsql security definer set search_path = '' as $$
declare
 a public.animals%rowtype;
 v_start date;
 v_entry_month date;
 v_first_charge date;
 v_total numeric(12,2);
 v_services text;
 v_lodge numeric(12,2);
 v_breed numeric(12,2);
 v_train numeric(12,2);
 v_client text;
 v_current date := date_trunc('month',current_date)::date;
begin
 if p_month is null or extract(day from p_month) <> 1 then
   raise exception 'Competencia invalida: informe o primeiro dia do mes.';
 end if;
 select * into a from public.animals where id=p_animal;
 if not found then return; end if;
 select billing_start_month into v_start from public.stay_billing_settings where singleton=true;
 -- Nunca apague cobranças emitidas se um cliente for excluído: a FK apenas
 -- desvincula o cliente. Isso preserva inclusive a competência atual.
 if a.owner_client_id is null then return; end if;
 -- A entrada/cadastro inaugura o mes de cortesia; o primeiro vencimento
 -- e sempre dia 10 do MES SEGUINTE. A competencia usa dia 01 internamente.
 -- Sem entrada, usar cadastro para novos animais; para cadastros antigos,
 -- nunca retroagir alem do mes de instalacao da v0.4.
 v_entry_month := coalesce(
   date_trunc('month',a.arrival_date)::date,
   greatest(v_start,date_trunc('month',a.created_at at time zone 'America/Sao_Paulo')::date)
 );
 v_first_charge := (v_entry_month + interval '1 month')::date;
 -- Mes de inicio e os anteriores nao geram cobranca.
 -- Se a competencia atual ja existia, mantem o registro isento (valor zero)
 -- para auditoria, em vez de recriar ou excluir o lancamento.
 if p_month < v_first_charge then
   if p_month = v_current then
     update public.stay_charges
        set amount=0, summary='Mes de entrada (isento - v0.4.4)'
      where animal_id=p_animal and reference_month=p_month and amount>0;
   end if;
   return;
 end if;
 if p_month > v_current
    or (a.departure_date is not null and date_trunc('month',a.departure_date)::date < p_month) then
   -- Atualizacao de saida cancela apenas cobranca do mes vigente.
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
 for a in select id,arrival_date,departure_date,created_at from public.animals
          where owner_client_id is not null loop
   -- A competencia inicial e sempre posterior ao mes de entrada/cadastro.
   v_first := (coalesce(
      date_trunc('month',a.arrival_date)::date,
      greatest(v_start,date_trunc('month',a.created_at at time zone 'America/Sao_Paulo')::date)
   ) + interval '1 month')::date;
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

COMMIT;
NOTIFY pgrst, 'reload schema';

-- Conferencia de ajustes (consulta opcional, somente no SQL Editor):
-- SELECT reference_month,animal_name_snapshot,original_amount,adjusted_at
-- FROM public.stay_start_month_adjustments ORDER BY adjusted_at DESC;
