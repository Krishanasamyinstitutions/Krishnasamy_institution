-- ============================================================================
-- CLEANUP: remove the OLD (superseded) per-schema admission module.
-- ============================================================================
-- The first admission design installed three tables into EVERY institution
-- schema (admissionapplication / admissiondocument / admissionstatushistory)
-- plus two public functions (add_admission_module, convert_application_to_student).
--
-- The new design uses a single public.admission table + allocate_admission_to_student
-- instead, so this drops all the old objects. Safe / idempotent — only drops
-- what exists. Does NOT touch students/parents/parentdetail or any real data.
-- ============================================================================

-- 1) Per-schema objects, across every institution-year schema
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
      -- tables (CASCADE also drops their triggers, policies, indexes)
      EXECUTE format('DROP TABLE IF EXISTS %I.admissionstatushistory CASCADE', sname);
      EXECUTE format('DROP TABLE IF EXISTS %I.admissiondocument      CASCADE', sname);
      EXECUTE format('DROP TABLE IF EXISTS %I.admissionapplication   CASCADE', sname);
      -- standalone sequences (not owned by the tables, so not auto-dropped)
      EXECUTE format('DROP SEQUENCE IF EXISTS %I.admissionapplication_apl_id_seq   CASCADE', sname);
      EXECUTE format('DROP SEQUENCE IF EXISTS %I.admissiondocument_doc_id_seq      CASCADE', sname);
      EXECUTE format('DROP SEQUENCE IF EXISTS %I.admissionstatushistory_ash_id_seq CASCADE', sname);
      -- trigger functions
      EXECUTE format('DROP FUNCTION IF EXISTS %I.set_apl_id()             CASCADE', sname);
      EXECUTE format('DROP FUNCTION IF EXISTS %I.set_admdoc_id()          CASCADE', sname);
      EXECUTE format('DROP FUNCTION IF EXISTS %I.set_ash_id()             CASCADE', sname);
      EXECUTE format('DROP FUNCTION IF EXISTS %I.fn_log_admission_status() CASCADE', sname);
      RAISE NOTICE 'Cleaned old admission objects from %', sname;
    END IF;
  END LOOP;
END $$;

-- 2) Old public helper functions
DROP FUNCTION IF EXISTS public.add_admission_module(text) CASCADE;
DROP FUNCTION IF EXISTS public.convert_application_to_student(text, bigint, text, text) CASCADE;

NOTIFY pgrst, 'reload config';

-- ----------------------------------------------------------------------------
-- OPTIONAL: if you also want to wipe the NEW public.admission table to start
-- the admission module from scratch, uncomment these:
--
--   DROP FUNCTION IF EXISTS public.allocate_admission_to_student(bigint, text, text, text, text) CASCADE;
--   DROP TABLE IF EXISTS public.admission CASCADE;
--   NOTIFY pgrst, 'reload config';
-- ----------------------------------------------------------------------------
