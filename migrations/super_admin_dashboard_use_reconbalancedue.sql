-- Align get_super_admin_dashboard_v2 with the institution-admin Fee Collection
-- card. Both should compute the "fee-only collected" amount using
-- reconbalancedue, so super-admin Total Collection matches the institution
-- admin's `Fee:` subtotal exactly.
--
-- Old formula (causes the mismatch):
--   total_pending  = SUM(balancedue) + pending_approval_fee
--   total_collected = total_demand - total_pending
--   ↑ Mixes balancedue (drops on payment) with recon-aware pending logic.
--
-- New formula (matches institution admin):
--   total_collected = SUM(feeamount - reconbalancedue) - pending_approval_fee
--   total_pending   = SUM(reconbalancedue)
--   pending_approval = SUM(paymentdetails - fineamount) for recon_status='P'

DROP FUNCTION IF EXISTS public.get_super_admin_dashboard_v2();

CREATE OR REPLACE FUNCTION public.get_super_admin_dashboard_v2()
RETURNS TABLE (
    ins_id           INT,
    insname          TEXT,
    inscode          TEXT,
    inshortname      TEXT,
    inslogo          TEXT,
    activestatus     SMALLINT,
    student_count    INT,
    total_demand     NUMERIC,
    total_collected  NUMERIC,
    total_pending    NUMERIC,
    pending_approval NUMERIC
) LANGUAGE plpgsql AS $$
DECLARE
    rec       RECORD;
    schema_n  TEXT;
    short_n   TEXT;
    yr_label  TEXT;
    demand    NUMERIC;
    collected NUMERIC;
    pending   NUMERIC;
    pending_a NUMERIC;
    stu_cnt   INT;
BEGIN
    FOR rec IN
        SELECT i.ins_id, i.insname, i.inscode, i.inshortname, i.inslogo, i.activestatus
        FROM   public.institution i
        ORDER  BY i.ins_id
    LOOP
        short_n := lower(rec.inshortname);
        SELECT iy.yrlabel INTO yr_label
        FROM   public.institutionyear iy
        WHERE  iy.ins_id = rec.ins_id AND iy.activestatus = 1
        ORDER  BY iy.iyr_id DESC
        LIMIT  1;
        IF yr_label IS NULL OR short_n IS NULL THEN
            ins_id := rec.ins_id; insname := rec.insname; inscode := rec.inscode;
            inshortname := rec.inshortname; inslogo := rec.inslogo;
            activestatus := rec.activestatus;
            student_count := 0; total_demand := 0; total_collected := 0;
            total_pending := 0; pending_approval := 0;
            RETURN NEXT;
            CONTINUE;
        END IF;
        schema_n := short_n || replace(yr_label, '-', '');

        IF NOT EXISTS (
            SELECT 1 FROM information_schema.schemata WHERE schema_name = schema_n
        ) THEN
            ins_id := rec.ins_id; insname := rec.insname; inscode := rec.inscode;
            inshortname := rec.inshortname; inslogo := rec.inslogo;
            activestatus := rec.activestatus;
            student_count := 0; total_demand := 0; total_collected := 0;
            total_pending := 0; pending_approval := 0;
            RETURN NEXT;
            CONTINUE;
        END IF;

        -- Pending approval fee portion: sum of payment allocations whose
        -- payment is still in recon_status='P', net of the fine portion.
        EXECUTE format($q$
            SELECT COALESCE(SUM(GREATEST(pd.transtotalamount - COALESCE(fd.fineamount, 0), 0)), 0)
            FROM   %1$I.payment p
            JOIN   %1$I.paymentdetails pd ON pd.pay_id = p.pay_id
            JOIN   %1$I.feedemand fd ON fd.dem_id = pd.dem_id
            WHERE  p.ins_id = %2$L
              AND  p.activestatus = 1
              AND  p.paystatus = 'C'
              AND  p.recon_status = 'P'
              AND  fd.activestatus = 1
        $q$, schema_n, rec.ins_id)
        INTO pending_a;

        -- total_demand and total_pending from feedemand;
        -- total_collected aggregated FROM the payment table to exactly
        -- mirror the institution-admin Fee Collection card:
        --   sum of payment.transtotalamount for paystatus='C' AND
        --   recon_status='R', minus the fine portion attributed to those
        --   payments (from feedemand.fineamount joined via pay_id).
        -- total_pending mirrors get_fee_totals (institution admin Pending
        -- Fees card): balancedue + pending-approval fee allocation, summed
        -- only for rows where the combined number is positive.
        EXECUTE format($q$
            WITH pending_alloc AS (
                SELECT pd.dem_id,
                       SUM(GREATEST(pd.transtotalamount - COALESCE(fd.fineamount,0), 0)) AS pending_fee
                FROM   %1$I.paymentdetails pd
                JOIN   %1$I.payment p ON p.pay_id = pd.pay_id
                LEFT JOIN %1$I.feedemand fd ON fd.dem_id = pd.dem_id
                WHERE  p.ins_id = %2$L AND p.paystatus = 'C'
                  AND  p.recon_status = 'P' AND p.activestatus = 1
                GROUP BY pd.dem_id
            )
            SELECT
                COALESCE(SUM(fd.feeamount), 0),
                COALESCE(SUM(fd.balancedue + COALESCE(pa.pending_fee, 0))
                  FILTER (WHERE (fd.balancedue + COALESCE(pa.pending_fee, 0)) > 0), 0)
            FROM   %1$I.feedemand fd
            LEFT JOIN pending_alloc pa ON pa.dem_id = fd.dem_id
            WHERE  fd.ins_id = %2$L AND fd.activestatus = 1
        $q$, schema_n, rec.ins_id)
        INTO demand, pending;

        EXECUTE format($q$
            WITH recon_pays AS (
                SELECT pay_id, transtotalamount
                FROM %1$I.payment
                WHERE ins_id = %2$L
                  AND activestatus = 1
                  AND paystatus = 'C'
                  AND recon_status = 'R'
            ),
            recon_fines AS (
                SELECT pay_id, COALESCE(SUM(fineamount), 0) AS fines
                FROM %1$I.feedemand
                WHERE pay_id IN (SELECT pay_id FROM recon_pays)
                GROUP BY pay_id
            )
            SELECT COALESCE(SUM(p.transtotalamount - COALESCE(f.fines, 0)), 0)
            FROM recon_pays p
            LEFT JOIN recon_fines f ON f.pay_id = p.pay_id
        $q$, schema_n, rec.ins_id)
        INTO collected;

        EXECUTE format($q$
            SELECT COUNT(*) FROM %I.students WHERE ins_id = %L AND activestatus = 1
        $q$, schema_n, rec.ins_id)
        INTO stu_cnt;

        ins_id := rec.ins_id; insname := rec.insname; inscode := rec.inscode;
        inshortname := rec.inshortname; inslogo := rec.inslogo;
        activestatus := rec.activestatus;
        student_count := stu_cnt;
        total_demand := demand;
        total_collected := GREATEST(collected, 0);
        total_pending := pending;
        pending_approval := pending_a;
        RETURN NEXT;
    END LOOP;
END $$;

GRANT EXECUTE ON FUNCTION public.get_super_admin_dashboard_v2() TO anon, authenticated;
