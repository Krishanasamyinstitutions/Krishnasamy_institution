-- Function: generate_overdue_fines
-- For each unpaid overdue demand, looks up the matching fine rule and creates a FINE
-- demand row in feedemand (paidstatus='U', balancedue=fine) if one does not already exist.
--
-- Usage:  SELECT public.generate_overdue_fines(p_ins_id);
-- Or for all institutions:  SELECT public.generate_overdue_fines_all();

CREATE OR REPLACE FUNCTION public.generate_overdue_fines(p_ins_id integer)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_schema text;
  v_inserted int := 0;
BEGIN
  v_schema := get_institution_schema(p_ins_id);
  IF v_schema IS NULL THEN RETURN 0; END IF;

  -- Skip if finerule table is missing
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema = v_schema AND table_name = 'finerule') THEN
    RETURN 0;
  END IF;

  EXECUTE format($f$
    WITH overdue AS (
      SELECT
        fd.dem_id, fd.ins_id, fd.inscode, fd.yr_id, fd.stu_id, fd.stuadmno,
        fd.stuclass, fd.courname, fd.demfeeyear, fd.demfeeterm, fd.demfeetype,
        fd.feeamount, fd.duedate, fd.createdby,
        (CURRENT_DATE - fd.duedate)::int AS overdue_days
      FROM %1$I.feedemand fd
      WHERE fd.ins_id = $1
        AND fd.activestatus = 1
        AND fd.demfeetype <> 'FINE'
        AND fd.balancedue > 0
        AND fd.duedate < CURRENT_DATE
        AND NOT EXISTS (
          SELECT 1 FROM %1$I.feedemand fn
          WHERE fn.activestatus = 1
            AND fn.demfeetype = 'FINE'
            AND fn.demno = 'FN' || fd.dem_id
        )
    ),
    matched AS (
      SELECT DISTINCT ON (o.dem_id)
        o.*,
        r.fine_type,
        r.fine_value,
        CASE WHEN r.feetype = o.demfeetype THEN 0 ELSE 1 END AS rule_priority
      FROM overdue o
      JOIN %1$I.finerule r
        ON r.ins_id = o.ins_id
       AND r.activestatus = 1
       AND o.overdue_days >= r.from_days
       AND (r.to_days IS NULL OR o.overdue_days <= r.to_days)
       AND (r.feetype = o.demfeetype OR r.feetype = 'ALL')
      ORDER BY o.dem_id, rule_priority, r.from_days DESC
    ),
    next_id AS (
      SELECT COALESCE(MAX(dem_id), 0) AS max_id FROM %1$I.feedemand
    ),
    numbered AS (
      SELECT m.*,
             (SELECT max_id FROM next_id) + ROW_NUMBER() OVER (ORDER BY m.dem_id) AS new_dem_id,
             CASE WHEN m.fine_type = 'PERCENT'
                  THEN ROUND(m.feeamount * m.fine_value / 100, 2)
                  ELSE m.fine_value END AS fine_amt
      FROM matched m
    )
    INSERT INTO %1$I.feedemand (
      dem_id, demno, demseqtype, ins_id, inscode, yr_id, stu_id, stuadmno,
      stuclass, courname, demfeeyear, demfeeterm, demfeetype,
      feeamount, conamount, paidamount, balancedue, reconbalancedue,
      duedate, paidstatus, createdby, activestatus
    )
    SELECT
      n.new_dem_id, 'FN' || n.dem_id, 'FINE', n.ins_id, n.inscode, n.yr_id,
      n.stu_id, n.stuadmno, n.stuclass, n.courname,
      n.demfeeyear, n.demfeeterm, 'FINE',
      n.fine_amt, 0, 0, n.fine_amt, n.fine_amt,
      n.duedate, 'U', COALESCE(n.createdby, 'system'), 1
    FROM numbered n
    WHERE n.fine_amt > 0
  $f$, v_schema) USING p_ins_id;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RETURN v_inserted;
END; $$;

-- Convenience: run for every institution
CREATE OR REPLACE FUNCTION public.generate_overdue_fines_all()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  rec RECORD;
  v_total int := 0;
  v_count int;
BEGIN
  FOR rec IN SELECT ins_id FROM public.institution WHERE activestatus = 1 LOOP
    v_count := public.generate_overdue_fines(rec.ins_id);
    v_total := v_total + COALESCE(v_count, 0);
  END LOOP;
  RETURN v_total;
END; $$;

GRANT EXECUTE ON FUNCTION public.generate_overdue_fines(integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.generate_overdue_fines_all() TO anon, authenticated;
