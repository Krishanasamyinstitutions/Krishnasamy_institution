-- Fix: reconcile_payments_batch failed to update feedemand.reconbalancedue
-- when a demand had more than one payment.
--
-- Cause: feedemand.pay_id holds ONE value, overwritten by the latest payment.
-- Step 2's WHERE pay_id = ANY(p_pay_ids) matched zero demand rows whenever a
-- later payment had replaced the id. The Pending Payment Report then kept
-- the stale reconbalancedue even though the bank had confirmed the earlier
-- partial payment.
--
-- Fix:
--   * Find affected demands via paymentdetails (the real many-to-many link).
--   * Recompute reconbalancedue as
--         feeamount - (sum of transtotalamount across payments with
--                       recon_status = 'R' and paystatus = 'C' for that demand)
--       so partial reconciliation across days is modelled correctly.

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

    -- 2. Recompute reconbalancedue from scratch for every demand touched by
    --    any of the now-reconciled payments. Using paymentdetails means we
    --    pick up demands whose feedemand.pay_id has since been overwritten by
    --    a later payment.
    EXECUTE format($q$
        UPDATE %1$I.feedemand fd
           SET reconbalancedue = GREATEST(
                 COALESCE(fd.feeamount, 0) - COALESCE(fd.conamount, 0) - COALESCE((
                     SELECT SUM(pd2.transtotalamount)
                     FROM %1$I.paymentdetails pd2
                     JOIN %1$I.payment p2
                       ON p2.pay_id = pd2.pay_id
                     WHERE pd2.dem_id = fd.dem_id
                       AND pd2.ins_id = %2$L
                       AND p2.paystatus = 'C'
                       AND p2.recon_status = 'R'
                 ), 0),
                 0)
         WHERE fd.ins_id = %2$L
           AND fd.dem_id IN (
               SELECT pd.dem_id
               FROM %1$I.paymentdetails pd
               WHERE pd.pay_id = ANY (%3$L::INT[])
                 AND pd.ins_id = %2$L
           )
    $q$, p_schema, p_ins_id, p_pay_ids);

    RETURN updated_count;
END $$;

GRANT EXECUTE ON FUNCTION public.reconcile_payments_batch(TEXT, INT, INT[], TEXT, TEXT, TEXT)
    TO anon, authenticated;
