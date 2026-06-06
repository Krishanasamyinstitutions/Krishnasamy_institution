-- ============================================================================
-- collectible flag on classfeedemand (the Class Fee Demand template).
-- ============================================================================
-- The "ALL" tick in Class Fee Demand means the fee applies to every student
-- and comes for collection (collectible). That state was previously only
-- persisted per-student on tempfeedemand/feedemand, so re-opening a saved
-- Class Fee Demand always showed the tick cleared. Storing it on the template
-- lets the screen restore the ALL tick when a Class/Sem/Admn Type is selected.
--
-- Backfill: existing template rows are marked collectible = true when a matching
-- collectible demand already exists in tempfeedemand or feedemand (same class +
-- term + fee type). Requires add_collectible_flag.sql to have run first.
-- Safe / idempotent.
-- ============================================================================

DO $$
DECLARE
  r record;
  sname text;
  has_temp_col boolean;
  has_fee_col boolean;
BEGIN
  FOR r IN
    SELECT DISTINCT lower(i.inshortname) || replace(iy.yrlabel, '-', '') AS schema_name
    FROM public.institution i
    JOIN public.institutionyear iy ON iy.ins_id = i.ins_id
    WHERE i.inshortname IS NOT NULL
  LOOP
    sname := r.schema_name;
    IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = sname) THEN
      CONTINUE;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                   WHERE n.nspname = sname AND c.relname = 'classfeedemand') THEN
      CONTINUE;
    END IF;

    EXECUTE format('ALTER TABLE %I.classfeedemand ADD COLUMN IF NOT EXISTS collectible boolean DEFAULT false NOT NULL', sname);

    -- Backfill from tempfeedemand (covers not-yet-approved demands).
    SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = sname AND table_name = 'tempfeedemand' AND column_name = 'collectible'
    ) INTO has_temp_col;
    IF has_temp_col THEN
      EXECUTE format($f$
        UPDATE %I.classfeedemand cfd SET collectible = true
        WHERE EXISTS (
          SELECT 1 FROM %I.tempfeedemand t
          WHERE t.stuclass = cfd.cfclass AND t.demfeeterm = cfd.cfterm
            AND t.demfeetype = cfd.cffeetype AND t.collectible = true
        )$f$, sname, sname);
    END IF;

    -- Backfill from feedemand (covers approved demands).
    SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = sname AND table_name = 'feedemand' AND column_name = 'collectible'
    ) INTO has_fee_col;
    IF has_fee_col THEN
      EXECUTE format($f$
        UPDATE %I.classfeedemand cfd SET collectible = true
        WHERE EXISTS (
          SELECT 1 FROM %I.feedemand fd
          WHERE fd.stuclass = cfd.cfclass AND fd.demfeeterm = cfd.cfterm
            AND fd.demfeetype = cfd.cffeetype AND fd.collectible = true
        )$f$, sname, sname);
    END IF;

    RAISE NOTICE 'classfeedemand.collectible applied to %', sname;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload config';
