-- ════════════════════════════════════════════════════════════════
-- Faster super admin dashboard: a single RPC that returns
--   per-institution: demand, collected, pending, pending_approval
-- aggregated directly from each tenant schema in one round trip.
-- ════════════════════════════════════════════════════════════════

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
    total_collected  NUMERIC,   -- sum(feeamount - reconbalancedue)
    total_pending    NUMERIC,   -- sum(reconbalancedue)
    pending_approval NUMERIC    -- sum(paymentdetails.transtotalamount - feedemand.fineamount)
                                --   for payments with recon_status = 'P'
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
        SELECT yrlabel INTO yr_label
        FROM   public.institutionyear
        WHERE  ins_id = rec.ins_id AND activestatus = 1
        ORDER  BY iyr_id DESC
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

        EXECUTE format($q$
            SELECT
                COALESCE(SUM(feeamount), 0),
                COALESCE(SUM(GREATEST(feeamount - reconbalancedue, 0)), 0),
                COALESCE(SUM(reconbalancedue), 0)
            FROM %I.feedemand
            WHERE ins_id = %L AND activestatus = 1
        $q$, schema_n, rec.ins_id)
        INTO demand, collected, pending;

        EXECUTE format($q$
            SELECT COALESCE(SUM(GREATEST(pd.transtotalamount - COALESCE(fd.fineamount, 0), 0)), 0)
            FROM   %1$I.payment p
            JOIN   %1$I.paymentdetails pd ON pd.pay_id = p.pay_id
            LEFT  JOIN %1$I.feedemand fd ON fd.dem_id = pd.dem_id
            WHERE  p.ins_id = %2$L
              AND  p.activestatus = 1
              AND  p.paystatus = 'C'
              AND  p.recon_status = 'P'
        $q$, schema_n, rec.ins_id)
        INTO pending_a;

        EXECUTE format($q$
            SELECT COUNT(*) FROM %I.students WHERE ins_id = %L AND activestatus = 1
        $q$, schema_n, rec.ins_id)
        INTO stu_cnt;

        ins_id := rec.ins_id; insname := rec.insname; inscode := rec.inscode;
        inshortname := rec.inshortname; inslogo := rec.inslogo;
        activestatus := rec.activestatus;
        student_count := stu_cnt;
        total_demand := demand;
        total_collected := collected;
        total_pending := pending;
        pending_approval := pending_a;
        RETURN NEXT;
    END LOOP;
END $$;

GRANT EXECUTE ON FUNCTION public.get_super_admin_dashboard_v2() TO anon, authenticated;
