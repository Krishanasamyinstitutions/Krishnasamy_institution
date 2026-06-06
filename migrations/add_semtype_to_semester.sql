-- ============================================================================
-- Semester master — add short name + type flag (Semester / Monthly / Yearly).
-- ============================================================================
-- Extends the per-institution `semester` table (see add_semester_master.sql)
-- with:
--   * semshort varchar(10)         — optional short label
--   * semtype  char(1) 'S'/'M'/'Y' — S = Semester, M = Monthly, Y = Yearly
-- Mirrors the `term` master's termtype flag. Safe / idempotent — re-runnable.
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
    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = sname)
       AND EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_schema = sname AND table_name = 'semester') THEN
      EXECUTE format('ALTER TABLE %I.semester ADD COLUMN IF NOT EXISTS semshort varchar(10)', sname);
      EXECUTE format('ALTER TABLE %I.semester ADD COLUMN IF NOT EXISTS semtype char(1) NOT NULL DEFAULT ''S''', sname);
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'semester_semtype_check'
          AND connamespace = sname::regnamespace
      ) THEN
        EXECUTE format(
          'ALTER TABLE %I.semester ADD CONSTRAINT semester_semtype_check '
          'CHECK (semtype IN (''S'', ''M'', ''Y''))', sname);
      END IF;
      RAISE NOTICE 'Updated semester master in %', sname;
    END IF;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload config';
