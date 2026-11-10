-- Haras F5E v0.4.5 | RELATORIOS (leitura)
-- Execute APOS a migracao v0.4.4, no projeto Supabase do Haras F5E.
-- Nao altera, exclui ou recria clientes, animais, cobrancas ou pagamentos.
-- Apenas adiciona a permissao de Relatorios e funcoes de consulta seguras.
BEGIN;

ALTER TABLE public.role_permissions DROP CONSTRAINT IF EXISTS role_permissions_module_check;
ALTER TABLE public.role_permissions ADD CONSTRAINT role_permissions_module_check
 CHECK (module IN ('resumo','clientes','despesas','funcionarios','animais',
    'pagamentos','hospedagem','treinamento','reproducao','exames',
    'recebimentos_estadia','valores','relatorios'));

-- Relatorios financeiros so podem ser consultados por funcoes autorizadas.
INSERT INTO public.role_permissions (role,module,can_view,can_create,can_edit,can_delete)
VALUES ('administrador','relatorios',true,false,false,false),
       ('gerente','relatorios',true,false,false,false),
       ('financeiro','relatorios',true,false,false,false)
ON CONFLICT(role,module) DO UPDATE SET
 can_view = EXCLUDED.can_view,
 can_create = false, can_edit = false, can_delete = false;

-- Resumo de clientes ativos. Valores do saldo seguem a MESMA regra da funcao
-- haras_client_stay_balance introduzida na v0.4.2:
-- todas as cobrancas do cliente, abatidas por pagamentos cuja competencia
-- (ou data, quando sem competencia) nao preceda o inicio do faturamento.
-- O total historico pago pode ser maior que o montante abatido no saldo.
CREATE OR REPLACE FUNCTION public.haras_report_clients(p_start date,p_end date)
RETURNS TABLE (
 client_id uuid, client_name text, client_number text,
 animal_count bigint, total_charged numeric, total_paid_credited numeric,
 total_paid_history numeric, balance numeric,
 period_charged numeric, period_paid numeric, period_payment_count bigint
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_billing_start date;
BEGIN
 IF NOT public.can_haras('relatorios','view') THEN
   RAISE EXCEPTION 'Sem permissao para consultar relatorios.';
 END IF;
 IF p_start IS NULL OR p_end IS NULL OR p_end < p_start
    OR EXTRACT(day FROM p_start) <> 1 OR EXTRACT(day FROM p_end) <> 1 THEN
   RAISE EXCEPTION 'Informe meses validos: inicio <= fim, ambos com dia 01.';
 END IF;
 SELECT s.billing_start_month INTO v_billing_start
 FROM public.stay_billing_settings s WHERE s.singleton=true;
 IF v_billing_start IS NULL THEN RAISE EXCEPTION 'Configuracao de faturamento ausente.'; END IF;
 RETURN QUERY
 SELECT c.id,c.name,c.client_number,
        COALESCE(a.quantity,0)::bigint,
        COALESCE(chg.charged,0)::numeric,
        COALESCE(pay.credited,0)::numeric,
        COALESCE(pay.all_paid,0)::numeric,
        (COALESCE(chg.charged,0)-COALESCE(pay.credited,0))::numeric,
        COALESCE(chg.period_amount,0)::numeric,
        COALESCE(pay.period_amount,0)::numeric,
        COALESCE(pay.period_count,0)::bigint
 FROM public.clients c
 LEFT JOIN LATERAL (
   SELECT COUNT(*)::bigint AS quantity FROM public.animals a
   WHERE a.owner_client_id=c.id
 ) a ON true
 LEFT JOIN LATERAL (
   SELECT COALESCE(SUM(sc.amount),0) AS charged,
          MIN(sc.reference_month) AS first_charge,
          COALESCE(SUM(sc.amount) FILTER (WHERE sc.reference_month >= p_start
             AND sc.reference_month < (p_end + INTERVAL '1 month')::date),0) AS period_amount
   FROM public.stay_charges sc WHERE sc.client_id=c.id
 ) chg ON true
 LEFT JOIN LATERAL (
   SELECT COALESCE(SUM(p.amount),0) AS all_paid,
          COALESCE(SUM(p.amount) FILTER (WHERE
            COALESCE(p.reference_month,p.payment_date) >=
              LEAST(v_billing_start,COALESCE(chg.first_charge,v_billing_start))
          ),0) AS credited,
          COALESCE(SUM(p.amount) FILTER (WHERE p.payment_date >= p_start
             AND p.payment_date < (p_end + INTERVAL '1 month')::date),0) AS period_amount,
          COUNT(*) FILTER (WHERE p.payment_date >= p_start
             AND p.payment_date < (p_end + INTERVAL '1 month')::date) AS period_count
   FROM public.payments p WHERE p.client_id=c.id
 ) pay ON true
 ORDER BY c.name,c.id;
END;
$$;
REVOKE ALL ON FUNCTION public.haras_report_clients(date,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.haras_report_clients(date,date) TO authenticated;

-- Pagamentos por DATA EFETIVA no periodo, nao pelo mes de referencia.
-- O texto livre (observacao) e os animais explicitamente vinculados ao
-- pagamento sao mostrados; pagamento de estadia nao e presumido como
-- quitacao automatica de determinado servico/animal.
CREATE OR REPLACE FUNCTION public.haras_report_payments(
 p_start date,p_end date,p_client uuid DEFAULT NULL,
 p_limit integer DEFAULT 100,p_offset integer DEFAULT 0
)
RETURNS TABLE (
 payment_id uuid, client_id uuid, client_name text, client_number text,
 payment_date date, reference_month date, payment_kind text, amount numeric,
 note text, animal_names text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT public.can_haras('relatorios','view') THEN
   RAISE EXCEPTION 'Sem permissao para consultar relatorios.';
 END IF;
 IF p_start IS NULL OR p_end IS NULL OR p_end < p_start
    OR EXTRACT(day FROM p_start) <> 1 OR EXTRACT(day FROM p_end) <> 1 THEN
   RAISE EXCEPTION 'Periodo invalido.';
 END IF;
 IF p_limit IS NULL OR p_limit < 1 OR p_limit > 200
    OR p_offset IS NULL OR p_offset < 0 THEN
   RAISE EXCEPTION 'Paginacao invalida (limite de 1 a 200).';
 END IF;
 RETURN QUERY
 SELECT p.id,p.client_id,
        COALESCE(c.name,NULLIF(BTRIM(p.client_name_snapshot),''),'Cliente excluido')::text,
        c.client_number,p.payment_date,p.reference_month,p.payment_kind,p.amount,p.note,
        (SELECT STRING_AGG(DISTINCT a.name,', ' ORDER BY a.name)
         FROM public.payment_animals pa
         JOIN public.animals a ON a.id=pa.animal_id
         WHERE pa.payment_id=p.id)::text
 FROM public.payments p
 LEFT JOIN public.clients c ON c.id=p.client_id
 WHERE p.payment_date >= p_start
   AND p.payment_date < (p_end + INTERVAL '1 month')::date
   AND (p_client IS NULL OR p.client_id=p_client)
 ORDER BY p.payment_date DESC,p.created_at DESC,p.id DESC
 LIMIT p_limit OFFSET p_offset;
END;
$$;
REVOKE ALL ON FUNCTION public.haras_report_payments(date,date,uuid,integer,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.haras_report_payments(date,date,uuid,integer,integer) TO authenticated;

-- Totais do periodo incluem tambem pagamentos historicos de clientes excluidos.
CREATE OR REPLACE FUNCTION public.haras_report_payment_stats(p_start date,p_end date)
RETURNS TABLE (payment_count bigint, payer_count bigint, paid_amount numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT public.can_haras('relatorios','view') THEN
   RAISE EXCEPTION 'Sem permissao para consultar relatorios.';
 END IF;
 IF p_start IS NULL OR p_end IS NULL OR p_end < p_start
    OR EXTRACT(day FROM p_start) <> 1 OR EXTRACT(day FROM p_end) <> 1 THEN
   RAISE EXCEPTION 'Periodo invalido.';
 END IF;
 RETURN QUERY
 SELECT COUNT(*)::bigint,
        COUNT(DISTINCT COALESCE(p.client_id::text,p.client_name_snapshot,p.id::text))::bigint,
        COALESCE(SUM(p.amount),0)::numeric
 FROM public.payments p
 WHERE p.payment_date>=p_start
   AND p.payment_date<(p_end+INTERVAL '1 month')::date;
END;
$$;
REVOKE ALL ON FUNCTION public.haras_report_payment_stats(date,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.haras_report_payment_stats(date,date) TO authenticated;

-- Detalhamento de servicos cobrados ao cliente no periodo: lista por animal,
-- mantendo a descricao fotografada na epoca do lancamento.
CREATE OR REPLACE FUNCTION public.haras_report_charges(
 p_client uuid,p_start date,p_end date
)
RETURNS TABLE (
 charge_id uuid, reference_month date, due_date date,
 animal_name text, description text, amount numeric
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT public.can_haras('relatorios','view') THEN
   RAISE EXCEPTION 'Sem permissao para consultar relatorios.';
 END IF;
 IF p_client IS NULL OR p_start IS NULL OR p_end IS NULL OR p_end < p_start
    OR EXTRACT(day FROM p_start) <> 1 OR EXTRACT(day FROM p_end) <> 1 THEN
   RAISE EXCEPTION 'Cliente ou periodo invalido.';
 END IF;
 RETURN QUERY
 SELECT sc.id,sc.reference_month,sc.due_date,sc.animal_name_snapshot,
        sc.summary,sc.amount
 FROM public.stay_charges sc
 WHERE sc.client_id=p_client AND sc.reference_month>=p_start
   AND sc.reference_month < (p_end + INTERVAL '1 month')::date
 ORDER BY sc.reference_month DESC,sc.animal_name_snapshot,sc.id;
END;
$$;
REVOKE ALL ON FUNCTION public.haras_report_charges(uuid,date,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.haras_report_charges(uuid,date,date) TO authenticated;

COMMIT;
NOTIFY pgrst, 'reload schema';
