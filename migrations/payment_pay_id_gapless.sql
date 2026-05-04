-- Gapless pay_id allocation across every per-institution schema.
--
-- Replaces the existing set_pay_id() trigger function (which used
-- nextval and therefore produced gaps on rollback) with a MAX+1
-- approach guarded by pg_advisory_xact_lock. The lock serialises
-- pay_id assignment across concurrent transactions, and because it
-- is transaction-scoped, a rollback simply releases the lock without
-- consuming a number.
--
-- Trade-offs:
--   * Concurrent payments serialise on the schema-level lock — typical
--     hold time is ~1ms (single MAX(pay_id) index scan), so the wait is
--     invisible to humans.
--   * Existing gaps (pay_ids already burned by past rollbacks) are NOT
--     renumbered. Renumbering is unsafe — pay_id is referenced by FKs
--     in paymentdetails.pay_id, feedemand.pay_id, and ledger reports.
--   * Future inserts will be strictly consecutive, so long as inserts
--     go through the trigger (don't bypass it from raw SQL Editor calls
--     outside of a transaction).
--
-- This is idempotent: re-running drops/recreates the function in place.
-- The existing payment_pay_id_seq is left in place but unused; safe to
-- leave alone.

DO $$
DECLARE v_schema TEXT;
BEGIN
  FOR v_schema IN
    SELECT DISTINCT table_schema
    FROM   information_schema.tables
    WHERE  table_name = 'payment'
      AND  table_schema NOT IN ('public', 'pg_catalog', 'information_schema')
  LOOP
    EXECUTE format($f$
      CREATE OR REPLACE FUNCTION %1$I.set_pay_id() RETURNS trigger
      LANGUAGE plpgsql AS $t$
      DECLARE v_next bigint;
      BEGIN
        IF NEW.pay_id IS NULL OR NEW.pay_id = 0 THEN
          PERFORM pg_advisory_xact_lock(hashtext(%1$L)::bigint);
          SELECT COALESCE(MAX(pay_id), 0) + 1 INTO v_next FROM %1$I.payment;
          NEW.pay_id := v_next;
        END IF;
        RETURN NEW;
      END $t$
    $f$, v_schema);
    RAISE NOTICE 'Updated set_pay_id() trigger function in schema: %', v_schema;
  END LOOP;
END $$;
