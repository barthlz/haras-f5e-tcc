-- HARAS F5E v0.4.4 | PREVIA DO MES DE ENTRADA (SOMENTE SELECT)
-- Nao altera qualquer dado. Execute antes da migracao 09.
-- Mostra exatamente as mensalidades hoje cobradas que passarao para R$ 0,00.
SELECT
  sc.client_name_snapshot AS cliente,
  sc.animal_name_snapshot AS animal,
  a.arrival_date AS entrada_no_haras,
  sc.reference_month AS competencia_a_isentar,
  sc.amount AS valor_a_descontar_do_saldo,
  sc.due_date AS vencimento_atual
FROM public.stay_charges sc
JOIN public.animals a ON a.id=sc.animal_id
CROSS JOIN public.stay_billing_settings settings
WHERE settings.singleton=true AND sc.amount > 0
  AND sc.reference_month=coalesce(
    date_trunc('month',a.arrival_date)::date,
    greatest(settings.billing_start_month,
      date_trunc('month',a.created_at at time zone 'America/Sao_Paulo')::date)
  )
ORDER BY sc.client_name_snapshot,sc.animal_name_snapshot,sc.reference_month;

-- Somatorio (opcional): execute separadamente, se desejar:
-- SELECT coalesce(sum(original_amount),0) AS total_ajustado
-- FROM public.stay_start_month_adjustments;
