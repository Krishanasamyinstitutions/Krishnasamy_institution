-- Update get_institution_course_summary to return fees (excl. fine) and fine separately.
-- Must be applied for every institution schema (e.g. kcet20262027), or the public wrapper
-- that dispatches by schema. Adjust schema name(s) as needed.

CREATE OR REPLACE FUNCTION public.get_institution_course_summary(p_ins_id INT)
RETURNS TABLE (
  course TEXT,
  class TEXT,
  students INT,
  fees NUMERIC,
  fine NUMERIC,
  collection NUMERIC,
  pending NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_schema TEXT;
BEGIN
  SELECT 'kcet' || EXTRACT(YEAR FROM CURRENT_DATE)::TEXT
         || (EXTRACT(YEAR FROM CURRENT_DATE)::INT + 1)::TEXT
    INTO v_schema;

  SELECT inshortname || EXTRACT(YEAR FROM CURRENT_DATE)::TEXT
         || (EXTRACT(YEAR FROM CURRENT_DATE)::INT + 1)::TEXT
    INTO v_schema
    FROM public.institution
    WHERE ins_id = p_ins_id;

  RETURN QUERY EXECUTE format($f$
    SELECT
      COALESCE(courname, 'Other')::TEXT AS course,
      COALESCE(stuclass, '')::TEXT      AS class,
      COUNT(DISTINCT stu_id)::INT       AS students,
      COALESCE(SUM(paidamount - COALESCE(fineamount, 0)), 0)::NUMERIC AS fees,
      COALESCE(SUM(fineamount), 0)::NUMERIC                            AS fine,
      COALESCE(SUM(paidamount), 0)::NUMERIC                            AS collection,
      COALESCE(SUM(balancedue), 0)::NUMERIC                            AS pending
    FROM %I.feedemand
    WHERE activestatus = 1
    GROUP BY courname, stuclass
    ORDER BY courname, stuclass
  $f$, v_schema);
END;
$$;
