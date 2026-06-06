-- ============================================================================
-- collectible flag — tempfeedemand + feedemand, carried through approval.
-- ============================================================================
-- Flow: Class Fee Demand stages a tempfeedemand per student for every fee line
-- with collectible = (ALL ticked). On approval, fn_approve_tempfeedemand copies
-- the row into feedemand AND carries the collectible flag. The fee-collection
-- query filters feedemand.collectible = true, so non-collectible demands are
-- recorded/approved but never offered for collection.
-- Existing demands default to collectible = true (unchanged). Safe / idempotent.
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
    IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = sname) THEN
      CONTINUE;
    END IF;

    IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
               WHERE n.nspname = sname AND c.relname = 'feedemand') THEN
      EXECUTE format('ALTER TABLE %I.feedemand ADD COLUMN IF NOT EXISTS collectible boolean DEFAULT true NOT NULL', sname);
    END IF;

    IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
               WHERE n.nspname = sname AND c.relname = 'tempfeedemand') THEN
      EXECUTE format('ALTER TABLE %I.tempfeedemand ADD COLUMN IF NOT EXISTS collectible boolean DEFAULT true NOT NULL', sname);
      -- Approval trigger: copy temp → feedemand carrying collectible.
      EXECUTE format('CREATE OR REPLACE FUNCTION %I.fn_approve_tempfeedemand() RETURNS trigger LANGUAGE plpgsql AS $t$ BEGIN IF NEW.isapproved = true AND (OLD.isapproved = false OR OLD.isapproved IS NULL) THEN INSERT INTO %I.feedemand (demno, ins_id, inscode, yr_id, stu_id, stuadmno, stuclass, courname, demfeeyear, demfeeterm, demfeetype, feeamount, con_id, conamount, balancedue, reconbalancedue, duedate, activestatus, createdat, createdby, paidstatus, paidamount, collectible) VALUES (NEW.demno, NEW.ins_id, NEW.inscode, NEW.yr_id, NEW.stu_id, NEW.stuadmno, NEW.stuclass, NEW.courname, NEW.demfeeyear, NEW.demfeeterm, NEW.demfeetype, NEW.feeamount, NEW.con_id, NEW.conamount, NEW.balancedue, NEW.feeamount, NEW.duedate, 1, NEW.createdat, NEW.createdby, ''U'', 0, COALESCE(NEW.collectible, true)); NEW.activestatus := 9; END IF; RETURN NEW; END; $t$', sname, sname);
    END IF;

    RAISE NOTICE 'collectible flag applied to %', sname;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload config';
