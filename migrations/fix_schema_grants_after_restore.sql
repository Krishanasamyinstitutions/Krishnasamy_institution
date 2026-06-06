-- ============================================================================
-- FIX: re-grant privileges on every institution-year schema after a
--      pg_dump --no-privileges restore.
-- ============================================================================
-- A `pg_dump ... --no-privileges` dump strips every GRANT. After restoring it
-- into a fresh Supabase project, the per-institution schemas (kcet20262027,
-- kp20262027, …) exist with data but anon/authenticated have NO privileges, so
-- the app gets "permission denied for schema ..." (SQLSTATE 42501) on every
-- tenant query. The `public` schema is unaffected because Supabase grants it by
-- default.
--
-- This re-applies the exact PERMISSIONS block that create_institution_schema
-- runs, for every existing institution schema, then re-exposes them to the
-- Data API. Safe to re-run.
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
      EXECUTE format('GRANT USAGE ON SCHEMA %I TO anon, authenticated', sname);
      EXECUTE format('GRANT ALL ON ALL TABLES IN SCHEMA %I TO anon, authenticated', sname);
      EXECUTE format('GRANT ALL ON ALL SEQUENCES IN SCHEMA %I TO anon, authenticated', sname);
      EXECUTE format('GRANT ALL ON ALL FUNCTIONS IN SCHEMA %I TO anon, authenticated', sname);
      EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT ALL ON TABLES TO anon, authenticated', sname);
      EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT ALL ON SEQUENCES TO anon, authenticated', sname);
      RAISE NOTICE 'Re-granted privileges on %', sname;
    END IF;
  END LOOP;
END $$;

-- Make sure every institution schema is exposed to PostgREST, then reload.
SELECT public.expose_all_schemas();
NOTIFY pgrst, 'reload config';
