-- ============================================================================
-- Add demographic / facility fields to public.admission.
-- ============================================================================
-- Community, Caste, Religion, Nationality, Transport mode (OWN/COLLEGE) and
-- Hostel (Y/N). Safe / idempotent. Run after the admission table already exists.
-- ============================================================================

ALTER TABLE public.admission ADD COLUMN IF NOT EXISTS community     varchar(30);
ALTER TABLE public.admission ADD COLUMN IF NOT EXISTS caste         varchar(30);
ALTER TABLE public.admission ADD COLUMN IF NOT EXISTS religion      varchar(30);
ALTER TABLE public.admission ADD COLUMN IF NOT EXISTS nationality   varchar(30);
ALTER TABLE public.admission ADD COLUMN IF NOT EXISTS transportmode varchar(10);  -- OWN / COLLEGE
ALTER TABLE public.admission ADD COLUMN IF NOT EXISTS hostel        char(1);      -- Y / N

-- Same fields on students in every institution schema, so class allocation
-- carries them from the admission record into the student record.
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
      EXECUTE format('ALTER TABLE %I.students ADD COLUMN IF NOT EXISTS community     varchar(30)', sname);
      EXECUTE format('ALTER TABLE %I.students ADD COLUMN IF NOT EXISTS caste         varchar(30)', sname);
      EXECUTE format('ALTER TABLE %I.students ADD COLUMN IF NOT EXISTS religion      varchar(30)', sname);
      EXECUTE format('ALTER TABLE %I.students ADD COLUMN IF NOT EXISTS nationality   varchar(30)', sname);
      EXECUTE format('ALTER TABLE %I.students ADD COLUMN IF NOT EXISTS transportmode varchar(10)', sname);
      EXECUTE format('ALTER TABLE %I.students ADD COLUMN IF NOT EXISTS hostel        char(1)', sname);
      RAISE NOTICE 'Added demographic columns to %.students', sname;
    END IF;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload config';
