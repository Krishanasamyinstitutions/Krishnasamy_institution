-- ============================================================================
-- Semester master — per institution schema (Master Data → Semester).
-- ============================================================================
-- Mirrors admissiontype / quota: a small smallint-PK master managed from the
-- Master Data screen via direct-lookup import. Safe / idempotent.
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
      EXECUTE format(
        'CREATE TABLE IF NOT EXISTS %I.semester ('
        'sem_id smallint PRIMARY KEY, semname varchar(30) NOT NULL, ins_id integer, '
        'activestatus smallint DEFAULT 1 NOT NULL, createdat timestamp DEFAULT now(), createdby varchar(50))',
        sname);
      EXECUTE format('GRANT ALL ON %I.semester TO anon, authenticated', sname);
      RAISE NOTICE 'Created semester master in %', sname;
    END IF;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload config';
