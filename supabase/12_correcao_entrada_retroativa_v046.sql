-- HARAS F5E TCC | v0.4.6: correcao auditavel de data de entrada.
-- PROJETO ACADEMICO SOMENTE. Exige backup validado antes de executar.
-- Aplicacao permanente: BEGIN ... COMMIT.
-- NAO modifica public.payments nem executa retificacao em massa.
-- Quando o inicio e adiado, zera cobrancas que perderam validade,
-- preservando cada lancamento e registrando valor anterior em auditoria.
-- Quando o inicio e antecipado, restaura apenas valores auditados ou
-- valores do mes corrente; nao inventa tarifas historicas ausentes.
BEGIN;

CREATE TABLE IF NOT EXISTS public.stay_arrival_change_audit (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  animal_id uuid NOT NULL,
  client_id uuid,
  old_arrival_date date,
  new_arrival_date date,
  charge_id uuid,
  reference_month date NOT NULL,
  old_amount numeric(12,2) NOT NULL,
  new_amount numeric(12,2) NOT NULL,
  old_summary text NOT NULL,
  new_summary text NOT NULL,
  changed_by uuid,
  changed_at timestamptz NOT NULL DEFAULT now(),
  reason text NOT NULL
);
ALTER TABLE public.stay_arrival_change_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.stay_arrival_change_audit FROM PUBLIC, anon, authenticated;

-- Checagem no servidor: retificar uma data que repercute no financeiro
-- exige permissao de editar recebimentos. SQL Editor/admin de banco,
-- onde auth.uid() nao e preenchido, continua sendo administrador do banco.
CREATE OR REPLACE FUNCTION public.haras_guard_arrival_correction()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NEW.arrival_date IS DISTINCT FROM OLD.arrival_date
     AND NEW.owner_client_id IS NOT NULL
     AND auth.uid() IS NOT NULL
     AND NOT public.can_haras('recebimentos_estadia','edit') THEN
    RAISE EXCEPTION 'Sem permissao financeira para alterar data de entrada.';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.haras_guard_arrival_correction() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_haras_guard_arrival_correction ON public.animals;
CREATE TRIGGER trg_haras_guard_arrival_correction
  BEFORE UPDATE OF arrival_date ON public.animals
  FOR EACH ROW EXECUTE FUNCTION public.haras_guard_arrival_correction();

CREATE OR REPLACE FUNCTION public.haras_reconcile_arrival_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_billing_start date;
  v_old_entry date;
  v_new_entry date;
  v_old_first date;
  v_new_first date;
  v_current date := pg_catalog.date_trunc('month', CURRENT_DATE)::date;
  v_month date;
  v_charge public.stay_charges%ROWTYPE;
  v_saved_amount numeric(12,2);
  v_saved_summary text;
  v_after_amount numeric(12,2);
  v_after_summary text;
BEGIN
  IF NEW.arrival_date IS NOT DISTINCT FROM OLD.arrival_date
     OR NEW.owner_client_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT billing_start_month INTO v_billing_start
    FROM public.stay_billing_settings WHERE singleton = true;
  IF v_billing_start IS NULL THEN
    RAISE EXCEPTION 'Configuracao de cobranca ausente.';
  END IF;

  v_old_entry := COALESCE(
    pg_catalog.date_trunc('month',OLD.arrival_date)::date,
    GREATEST(v_billing_start,
      pg_catalog.date_trunc('month',OLD.created_at AT TIME ZONE 'America/Sao_Paulo')::date)
  );
  v_new_entry := COALESCE(
    pg_catalog.date_trunc('month',NEW.arrival_date)::date,
    GREATEST(v_billing_start,
      pg_catalog.date_trunc('month',NEW.created_at AT TIME ZONE 'America/Sao_Paulo')::date)
  );
  v_old_first := (v_old_entry + INTERVAL '1 month')::date;
  v_new_first := (v_new_entry + INTERVAL '1 month')::date;

  -- Sem mudanca de competencia, nao existe ajuste a fazer.
  IF v_old_first = v_new_first THEN
    RETURN NEW;
  END IF;

  IF v_new_first > v_old_first THEN
    -- ADIOU a entrada: mensalidades entre os dois inicios deixam de valer.
    FOR v_charge IN
      SELECT * FROM public.stay_charges sc
      WHERE sc.animal_id = NEW.id
        AND sc.reference_month >= v_old_first
        AND sc.reference_month < v_new_first
        AND sc.reference_month <= v_current
        AND sc.amount > 0
      ORDER BY sc.reference_month
      FOR UPDATE
    LOOP
      INSERT INTO public.stay_arrival_change_audit
        (animal_id,client_id,old_arrival_date,new_arrival_date,
         charge_id,reference_month,old_amount,new_amount,
         old_summary,new_summary,changed_by,reason)
      VALUES
        (NEW.id,v_charge.client_id,OLD.arrival_date,NEW.arrival_date,
         v_charge.id,v_charge.reference_month,v_charge.amount,0,
         v_charge.summary,'Mes de entrada isento (data retificada)',
         auth.uid(),'adiamento de entrada');

      UPDATE public.stay_charges
      SET amount=0, summary='Mes de entrada isento (data retificada)'
      WHERE id=v_charge.id;
    END LOOP;

  ELSE
    -- ANTECIPOU a entrada: jamais inventar tarifas historicas.
    FOR v_month IN
      SELECT gs::date
      FROM pg_catalog.generate_series(
        v_new_first::timestamp,
        LEAST((v_old_first - INTERVAL '1 month')::date,v_current)::timestamp,
        INTERVAL '1 month'
      ) AS gs
    LOOP
      IF NEW.departure_date IS NOT NULL AND
         v_month > pg_catalog.date_trunc('month',NEW.departure_date)::date THEN
        CONTINUE;
      END IF;
      IF NEW.billing_category <> 'Padrão' THEN
        CONTINUE; -- Categoria isenta: permanece sem cobranca.
      END IF;

      SELECT * INTO v_charge
      FROM public.stay_charges sc
      WHERE sc.animal_id=NEW.id AND sc.reference_month=v_month
      FOR UPDATE;

      IF FOUND AND v_charge.amount > 0 THEN
        CONTINUE;
      END IF;

      IF FOUND THEN
        SELECT au.old_amount, au.old_summary
          INTO v_saved_amount, v_saved_summary
        FROM public.stay_arrival_change_audit au
        WHERE au.charge_id=v_charge.id
          AND au.old_amount>0 AND au.new_amount=0
        ORDER BY au.changed_at DESC,au.id DESC
        LIMIT 1;

        IF NOT FOUND THEN
          -- Aproveitar tambem a auditoria original da v0.4.4,
          -- caso a mensalidade tenha sido isentada naquela migracao.
          SELECT adj.original_amount, adj.original_summary
            INTO v_saved_amount, v_saved_summary
          FROM public.stay_start_month_adjustments adj
          WHERE adj.charge_id=v_charge.id
            AND adj.original_amount>0
          LIMIT 1;
        END IF;

        IF FOUND THEN
          INSERT INTO public.stay_arrival_change_audit
            (animal_id,client_id,old_arrival_date,new_arrival_date,
             charge_id,reference_month,old_amount,new_amount,
             old_summary,new_summary,changed_by,reason)
          VALUES
            (NEW.id,v_charge.client_id,OLD.arrival_date,NEW.arrival_date,
             v_charge.id,v_month,v_charge.amount,v_saved_amount,
             v_charge.summary,v_saved_summary,auth.uid(),
             'restauracao de mensalidade anteriormente auditada');
          UPDATE public.stay_charges
          SET amount=v_saved_amount,summary=v_saved_summary
          WHERE id=v_charge.id;
          CONTINUE;
        END IF;
      END IF;

      IF v_month < v_current THEN
        RAISE EXCEPTION
          'Antecipacao requer conferencia manual da tarifa historica de %; nenhuma alteracao foi salva.',
          v_month;
      END IF;

      -- So o mes corrente pode ser reconstruido com a tarifa vigente.
      PERFORM public.haras_write_stay_charge(NEW.id,v_month);

      SELECT sc.amount,sc.summary INTO v_after_amount,v_after_summary
      FROM public.stay_charges sc
      WHERE sc.animal_id=NEW.id AND sc.reference_month=v_month;
      IF FOUND AND v_after_amount>0 THEN
        INSERT INTO public.stay_arrival_change_audit
          (animal_id,client_id,old_arrival_date,new_arrival_date,
           charge_id,reference_month,old_amount,new_amount,
           old_summary,new_summary,changed_by,reason)
        SELECT NEW.id,NEW.owner_client_id,OLD.arrival_date,NEW.arrival_date,
          sc.id,v_month,COALESCE(v_charge.amount,0),v_after_amount,
          COALESCE(v_charge.summary,'Sem cobranca anterior'),v_after_summary,
          auth.uid(),'geracao/recalculo de mensalidade do mes vigente'
        FROM public.stay_charges sc
        WHERE sc.animal_id=NEW.id AND sc.reference_month=v_month;
      END IF;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.haras_reconcile_arrival_change() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_aaa_haras_reconcile_arrival_change ON public.animals;
-- Executa ANTES do gatilho antigo trg_haras_animal_stay_changed,
-- para registrar o valor anterior do mes vigente antes da atualizacao dele.
CREATE TRIGGER trg_aaa_haras_reconcile_arrival_change
  AFTER UPDATE OF arrival_date ON public.animals
  FOR EACH ROW EXECUTE FUNCTION public.haras_reconcile_arrival_change();

COMMIT;
