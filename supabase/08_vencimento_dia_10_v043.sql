-- HARAS F5E v0.4.3 | VENCIMENTO FIXO DIA 10
-- Aplicar APOS v0.4.2 no mesmo banco, preferencialmente apos backup.
-- Esta migracao NAO exclui e NAO recalcula mensalidades, clientes ou pagamentos.
-- A competencia/reference_month segue no primeiro dia (01) por necessidade contábil.
-- A data real de vencimento sera dia 10 do MES da competencia.
-- Coluna gerada: tanto registros anteriores quanto futuras mensalidades ficam sincronizados.
BEGIN;

ALTER TABLE public.stay_charges
  ADD COLUMN IF NOT EXISTS due_date date
    GENERATED ALWAYS AS (reference_month + 9) STORED;

-- Se existir uma coluna due_date criada manualmente e sem calculo automatico,
-- pare em vez de concluir uma migracao com vencimentos incorretos.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname='public' AND c.relname='stay_charges'
      AND a.attname='due_date' AND a.attgenerated='s' AND NOT a.attisdropped
  ) THEN
    RAISE EXCEPTION 'A coluna stay_charges.due_date ja existe, mas nao e uma coluna gerada. Confira antes de prosseguir.';
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_haras_stay_charges_due_date
  ON public.stay_charges(due_date);

COMMIT;
NOTIFY pgrst, 'reload schema';

-- Conferir (consulta opcional):
-- SELECT reference_month, due_date, amount FROM public.stay_charges
-- ORDER BY reference_month DESC LIMIT 20;
