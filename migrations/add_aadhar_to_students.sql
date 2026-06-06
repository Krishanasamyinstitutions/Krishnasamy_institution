-- ============================================================================
-- Add aadharno to students (for the admission module's class allocation).
-- ============================================================================
-- The allocate_admission_to_student RPC copies aadharno into students, so the
-- column must exist. Adds it to every institution-year schema's students table.
-- Also drops the now-unused emisno column from public.admission if present.
-- Safe / idempotent.
-- ============================================================================

DO $$
DECLARE
  r record;
  sname text;
BEGIN
  FOR r IN
    SELECT DISTINCT lower(i.inshortname) || replace(iy.yrlabel, '-', '') AS schema_name
    FROM public.institution i
    JOIN public.institutionyear iy ON iy.ins_id = i.ins_id
    WHERE i.inshortname IS NOT NULL
  LOOP
    sname := r.schema_name;
    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = sname) THEN
      EXECUTE format('ALTER TABLE %I.students ADD COLUMN IF NOT EXISTS aadharno varchar(20)', sname);
      RAISE NOTICE 'Added aadharno to %.students', sname;
    END IF;
  END LOOP;
END $$;

-- Remove the dropped emisno column from public.admission (if the table exists)
ALTER TABLE IF EXISTS public.admission DROP COLUMN IF EXISTS emisno;

NOTIFY pgrst, 'reload config';
