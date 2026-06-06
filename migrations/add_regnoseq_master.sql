-- ============================================================================
-- Register Number Sequencing master — per institution schema.
-- ============================================================================
-- Defines how admission register numbers are formatted/generated:
--   rnsname   - description (e.g. "B.Tech 2026")
--   rnsmode   - 'P' prefix | 'S' suffix
--   rnsaffix  - the prefix/suffix text
--   rnsstart / rnsend / rnswidth - numbering range + zero-pad width
--   rnscurrent- running counter
--   division  - free text
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
      EXECUTE format(
        'CREATE TABLE IF NOT EXISTS %I.regnoseq ('
        'rns_id smallint PRIMARY KEY, rnsname varchar(50) NOT NULL, '
        'rnsmode char(1) DEFAULT ''P'' NOT NULL CHECK (rnsmode IN (''P'',''S'')), '
        'rnsaffix varchar(15), rnsstart numeric(9,0) DEFAULT 1, rnsend numeric(9,0), '
        'rnswidth smallint DEFAULT 4, rnscurrent numeric(9,0) DEFAULT 0, division varchar(50), '
        'ins_id integer, activestatus smallint DEFAULT 1 NOT NULL, '
        'createdat timestamp DEFAULT now(), createdby varchar(50))',
        sname);
      EXECUTE format('GRANT ALL ON %I.regnoseq TO anon, authenticated', sname);
      RAISE NOTICE 'Created regnoseq master in %', sname;
    END IF;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload config';
