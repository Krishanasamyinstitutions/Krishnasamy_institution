-- ════════════════════════════════════════════════════════════════
-- perf_round_two.sql — bulk reconciliation RPC
-- Replaces the N-round-trip update loop in bank_reconciliation_screen
-- with a single call that marks payments reconciled AND snapshots
-- feedemand.reconbalancedue in one transaction per tenant schema.
-- ════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.reconcile_payments_batch(TEXT, INT, INT[], TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.reconcile_payments_batch(
    p_schema        TEXT,
    p_ins_id        INT,
    p_pay_ids       INT[],
    p_user          TEXT,
    p_bank_ref      TEXT DEFAULT NULL,
    p_bank_date     TEXT DEFAULT NULL
) RETURNS INT LANGUAGE plpgsql AS $$
DECLARE
    updated_count INT := 0;
BEGIN
    IF p_pay_ids IS NULL OR array_length(p_pay_ids, 1) IS NULL THEN
        RETURN 0;
    END IF;

    -- 1. Mark selected payments reconciled
    EXECUTE format($q$
        UPDATE %I.payment
           SET recon_status   = 'R',
               reconciled_by  = %L,
               reconciled_date = now(),
               bank_reference = COALESCE(NULLIF(%L, ''), bank_reference),
               bank_date      = COALESCE(%L::timestamp, bank_date)
         WHERE ins_id = %L
           AND pay_id = ANY (%L::INT[])
    $q$, p_schema, p_user, COALESCE(p_bank_ref, ''), p_bank_date, p_ins_id, p_pay_ids);

    GET DIAGNOSTICS updated_count = ROW_COUNT;

    -- 2. Snapshot feedemand.reconbalancedue from the live balancedue
    EXECUTE format($q$
        UPDATE %I.feedemand
           SET reconbalancedue = balancedue
         WHERE ins_id = %L
           AND pay_id = ANY (%L::INT[])
    $q$, p_schema, p_ins_id, p_pay_ids);

    RETURN updated_count;
END $$;

GRANT EXECUTE ON FUNCTION public.reconcile_payments_batch(TEXT, INT, INT[], TEXT, TEXT, TEXT)
    TO anon, authenticated;
