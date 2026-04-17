-- ════════════════════════════════════════════════════════════════
-- REPORT RPCs (move heavy aggregation into Postgres so the Reports
-- tab loads instantly instead of hanging while Flutter pivots).
--
-- Pass the tenant schema name from the client (SupabaseService.currentSchema).
-- ════════════════════════════════════════════════════════════════

-- 1. DAILY COLLECTION  (receipt-wise pivot)
DROP FUNCTION IF EXISTS public.get_daily_collection_report(TEXT, INT, DATE, DATE);
CREATE OR REPLACE FUNCTION public.get_daily_collection_report(
    p_schema TEXT, p_ins_id INT, p_from DATE, p_to DATE
) RETURNS TABLE (
    pay_id BIGINT, paynumber TEXT, stuadmno TEXT, stuname TEXT,
    courname TEXT, stuclass TEXT, paymethod TEXT,
    fees_json JSONB, fine NUMERIC, total NUMERIC, paydate DATE
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY EXECUTE format($f$
        SELECT  p.pay_id::BIGINT,
                p.paynumber::TEXT,
                s.stuadmno::TEXT,
                s.stuname::TEXT,
                s.courname::TEXT,
                s.stuclass::TEXT,
                p.paymethod::TEXT,
                COALESCE(jsonb_object_agg(fd.demfeetype, pd.transtotalamount)
                         FILTER (WHERE fd.demfeetype IS NOT NULL),
                         '{}'::jsonb) AS fees_json,
                COALESCE(SUM(fd.fineamount), 0)::NUMERIC AS fine,
                p.transtotalamount::NUMERIC AS total,
                p.paydate::DATE
        FROM    %1$I.payment p
        LEFT JOIN %1$I.paymentdetails pd ON pd.pay_id = p.pay_id
        LEFT JOIN %1$I.feedemand fd ON fd.dem_id = pd.dem_id
        LEFT JOIN %1$I.students s ON s.stu_id = p.stu_id
        WHERE   p.ins_id = %2$L AND p.activestatus = 1
            AND p.paydate::DATE >= %3$L AND p.paydate::DATE <= %4$L
        GROUP BY p.pay_id, p.paynumber, p.paymethod, p.transtotalamount, p.paydate,
                 s.stuadmno, s.stuname, s.courname, s.stuclass
        ORDER BY p.paynumber
    $f$, p_schema, p_ins_id, p_from, p_to);
END $$;

-- 2. PENDING PAYMENT REPORT
CREATE OR REPLACE FUNCTION public.get_pending_payment_report(
    p_schema TEXT, p_ins_id INT
) RETURNS TABLE (
    courname TEXT, stuclass TEXT, semester TEXT,
    admname TEXT, stuadmno TEXT, stuname TEXT,
    pending NUMERIC, concession NUMERIC,
    quoname TEXT, stumobile TEXT
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY EXECUTE format($f$
        SELECT  s.courname::TEXT, s.stuclass::TEXT,
                fd.demfeeterm::TEXT AS semester,
                s.admname::TEXT, s.stuadmno::TEXT, s.stuname::TEXT,
                SUM(fd.balancedue)::NUMERIC AS pending,
                SUM(fd.conamount)::NUMERIC AS concession,
                s.quoname::TEXT, s.stumobile::TEXT
        FROM    %1$I.feedemand fd
        JOIN    %1$I.students s ON s.stu_id = fd.stu_id
        WHERE   fd.ins_id = %2$L AND fd.activestatus = 1 AND fd.balancedue > 0
        GROUP BY s.courname, s.stuclass, fd.demfeeterm,
                 s.admname, s.stuadmno, s.stuname, s.quoname, s.stumobile
        ORDER BY s.courname, s.stuclass, fd.demfeeterm, s.stuadmno
    $f$, p_schema, p_ins_id);
END $$;

-- 3. CONSOLIDATED FEE COLLECTION STATUS
CREATE OR REPLACE FUNCTION public.get_consolidated_status_report(
    p_schema TEXT, p_ins_id INT
) RETURNS TABLE (
    courname TEXT, stuclass TEXT, strength INT,
    semester TEXT, category TEXT, stud_count INT, type TEXT,
    due NUMERIC, concession NUMERIC, net_demand NUMERIC,
    paid NUMERIC, balance NUMERIC
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY EXECUTE format($f$
        WITH class_strength AS (
            SELECT courname, stuclass, COUNT(DISTINCT stu_id)::INT AS strength
            FROM   %1$I.students WHERE ins_id = %2$L AND activestatus = 1
            GROUP BY courname, stuclass
        )
        SELECT  s.courname::TEXT, s.stuclass::TEXT,
                cs.strength,
                fd.demfeeterm::TEXT AS semester,
                COALESCE(NULLIF(s.quoname, ''), 'GENERAL')::TEXT AS category,
                COUNT(DISTINCT s.stu_id)::INT AS stud_count,
                'Regular'::TEXT AS type,
                SUM(fd.feeamount)::NUMERIC AS due,
                SUM(fd.conamount)::NUMERIC AS concession,
                (SUM(fd.feeamount) - SUM(fd.conamount))::NUMERIC AS net_demand,
                SUM(fd.paidamount)::NUMERIC AS paid,
                SUM(fd.balancedue)::NUMERIC AS balance
        FROM    %1$I.feedemand fd
        JOIN    %1$I.students s ON s.stu_id = fd.stu_id
        LEFT JOIN class_strength cs
               ON cs.courname = s.courname AND cs.stuclass = s.stuclass
        WHERE   fd.ins_id = %2$L AND fd.activestatus = 1
        GROUP BY s.courname, s.stuclass, cs.strength,
                 fd.demfeeterm, COALESCE(NULLIF(s.quoname, ''), 'GENERAL')
        ORDER BY s.courname, s.stuclass, fd.demfeeterm, category
    $f$, p_schema, p_ins_id);
END $$;

-- 4. STUDENT LEDGER
CREATE OR REPLACE FUNCTION public.get_student_ledger_report(
    p_schema TEXT, p_ins_id INT, p_stuadmno TEXT
) RETURNS TABLE (
    demfeeterm TEXT, demfeetype TEXT,
    feeamount NUMERIC, conamount NUMERIC, paidamount NUMERIC,
    balancedue NUMERIC, paynumber TEXT, paydate DATE,
    duedate DATE
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY EXECUTE format($f$
        SELECT  fd.demfeeterm::TEXT, fd.demfeetype::TEXT,
                fd.feeamount::NUMERIC, fd.conamount::NUMERIC,
                fd.paidamount::NUMERIC, fd.balancedue::NUMERIC,
                p.paynumber::TEXT, p.paydate, fd.duedate
        FROM    %1$I.feedemand fd
        LEFT JOIN %1$I.payment p ON p.pay_id = fd.pay_id
        WHERE   fd.ins_id = %2$L AND fd.activestatus = 1
            AND fd.stuadmno = %3$L
        ORDER BY fd.duedate
    $f$, p_schema, p_ins_id, p_stuadmno);
END $$;

GRANT EXECUTE ON FUNCTION public.get_daily_collection_report(TEXT, INT, DATE, DATE) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_pending_payment_report(TEXT, INT)               TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_consolidated_status_report(TEXT, INT)           TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_student_ledger_report(TEXT, INT, TEXT)          TO anon, authenticated;
