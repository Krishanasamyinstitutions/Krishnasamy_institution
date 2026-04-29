-- Per-institution schema: drop cour_id from class and add succeedingclass.
-- succeedingclass holds the name of the next class in the promotion ladder
-- (e.g., 'I Year' → 'II Year'). NULL means terminal class.

DO $$
DECLARE
  v_schema text;
BEGIN
  FOR v_schema IN
    SELECT schema_name FROM information_schema.schemata
    WHERE schema_name ~ '^[a-z]+[0-9]{8}$'   -- tenant schemas like kcet20262027
  LOOP
    -- Drop FK then the column (use IF EXISTS so re-runs are safe)
    EXECUTE format('ALTER TABLE %I.class DROP CONSTRAINT IF EXISTS fk_class_course', v_schema);
    EXECUTE format('ALTER TABLE %I.class DROP COLUMN IF EXISTS cour_id', v_schema);
    -- Add the new column
    EXECUTE format('ALTER TABLE %I.class ADD COLUMN IF NOT EXISTS succeedingclass varchar(20)', v_schema);
  END LOOP;
END $$;
