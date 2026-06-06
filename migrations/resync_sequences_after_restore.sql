-- ============================================================================
-- Resync all per-schema sequences after a pg_dump/pg_restore.
-- ============================================================================
-- A plain data restore reloads rows with their original explicit IDs but does
-- NOT advance the backing sequences. The institution schemas assign IDs via
-- BEFORE-INSERT triggers that call nextval('<table>_<col>_seq'), so a stale
-- sequence hands out an ID that already exists → unique-violation
-- ("That record already exists") on the next insert. Seen on Class Allocation
-- (students_stu_id_seq) and Fee Master (feegroup/feetype/classfeedemand).
--
-- This walks every tenant schema, matches each sequence to its owning
-- table.column by the "<table>_<column>_seq" naming convention, and setval()s
-- it to MAX(column) so the next nextval() is MAX+1. Idempotent — safe to run
-- after every restore.
-- ============================================================================

DO $$
DECLARE
  r    record;   -- tenant schema
  s    record;   -- sequence in that schema
  tbl  text;
  col  text;
  maxv bigint;
  seqfqn text;
BEGIN
  FOR r IN
    SELECT DISTINCT lower(i.inshortname) || replace(iy.yrlabel, '-', '') AS sname
    FROM public.institution i
    JOIN public.institutionyear iy ON iy.ins_id = i.ins_id
    WHERE i.inshortname IS NOT NULL
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = r.sname) THEN
      CONTINUE;
    END IF;

    FOR s IN
      SELECT c.relname AS seqname
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = r.sname AND c.relkind = 'S'
    LOOP
      -- Resolve the owning table + column from the sequence name. Matching
      -- against the actual columns avoids ambiguity from underscores in names.
      SELECT cols.table_name, cols.column_name
        INTO tbl, col
      FROM information_schema.columns cols
      WHERE cols.table_schema = r.sname
        AND cols.table_name || '_' || cols.column_name || '_seq' = s.seqname
      LIMIT 1;

      IF tbl IS NULL THEN
        CONTINUE;  -- sequence we can't map by convention; leave it alone
      END IF;

      EXECUTE format('SELECT COALESCE(MAX(%I), 0) FROM %I.%I', col, r.sname, tbl)
        INTO maxv;

      seqfqn := r.sname || '.' || s.seqname;
      -- is_called = true when rows exist (next = MAX+1); false when empty
      -- (next = 1, so the first id isn't skipped).
      EXECUTE format('SELECT setval(%L, %s, %s)',
                     seqfqn,
                     GREATEST(maxv, 1),
                     CASE WHEN maxv > 0 THEN 'true' ELSE 'false' END);

      RAISE NOTICE 'resync %.% -> %', r.sname, s.seqname, GREATEST(maxv, 1);
    END LOOP;
  END LOOP;
END $$;
