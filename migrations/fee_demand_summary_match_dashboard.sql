-- Make get_fee_demand_summary use the same pending-calc rules as get_fee_totals
-- so the Fee Demand screen pending column matches the dashboard "Pending Fees" card.
-- Changes:
--   1. JOIN students (so demands for inactive/missing students are excluded)
--   2. Filter rows where (balancedue + pending_alloc) <= 0 (skip overpaid rows)

CREATE OR REPLACE FUNCTION public.get_fee_demand_summary(p_ins_id integer)
RETURNS TABLE(stuclass text, courname text, student_count bigint, fee_types text[], total_demand numeric, total_concession numeric, total_paid numeric, total_pending numeric, total_fine numeric)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v text;
BEGIN
  v := get_institution_schema(p_ins_id);
  IF v IS NULL THEN RETURN; END IF;
  RETURN QUERY EXECUTE format($f$
    WITH pending_alloc AS (
      SELECT pd.dem_id,
             SUM(GREATEST(pd.transtotalamount - COALESCE(fd.fineamount,0), 0)) AS pending_fee,
             SUM(LEAST(pd.transtotalamount, COALESCE(fd.fineamount,0))) AS pending_fine
      FROM %1$I.paymentdetails pd
      JOIN %1$I.payment p ON p.pay_id = pd.pay_id
      LEFT JOIN %1$I.feedemand fd ON fd.dem_id = pd.dem_id
      WHERE p.ins_id = $1 AND p.paystatus = 'C'
        AND p.recon_status = 'P' AND p.activestatus = 1
      GROUP BY pd.dem_id
    )
    SELECT fd.stuclass::text,
           COALESCE(fd.courname,'Other')::text,
           COUNT(DISTINCT fd.stuadmno)::bigint,
           ARRAY_AGG(DISTINCT fd.demfeetype::text ORDER BY fd.demfeetype::text)
             FILTER(WHERE fd.demfeetype IS NOT NULL AND fd.demfeetype<>''),
           SUM(fd.feeamount),
           SUM(fd.conamount),
           GREATEST(
             COALESCE(SUM(fd.paidamount),0)
               - COALESCE(SUM(fd.fineamount) FILTER (WHERE fd.paidstatus='P' OR fd.paidamount > 0),0)
               - COALESCE(SUM(pa.pending_fee),0),
             0
           ) AS total_paid,
           COALESCE(SUM(fd.balancedue + COALESCE(pa.pending_fee, 0))
             FILTER (WHERE (fd.balancedue + COALESCE(pa.pending_fee, 0)) > 0), 0
           ) AS total_pending,
           GREATEST(
             COALESCE(SUM(fd.fineamount) FILTER (WHERE fd.paidstatus='P' OR fd.paidamount > 0),0)
               - COALESCE(SUM(pa.pending_fine),0),
             0
           ) AS total_fine
    FROM %1$I.feedemand fd
    JOIN %1$I.students s ON s.stu_id = fd.stu_id
    LEFT JOIN pending_alloc pa ON pa.dem_id = fd.dem_id
    WHERE fd.ins_id=$1 AND fd.activestatus=1
    GROUP BY fd.stuclass, fd.courname
    ORDER BY fd.courname, fd.stuclass
  $f$, v) USING p_ins_id;
END; $$;
