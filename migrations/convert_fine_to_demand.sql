-- Convert fineamount column to separate FINE demand rows
-- Run this once after deploying the new code

DO $$
DECLARE
    schema_name TEXT;
BEGIN
    FOR schema_name IN
        SELECT nspname FROM pg_namespace
        WHERE nspname NOT IN ('public', 'pg_catalog', 'information_schema', 'pg_toast', 'extensions', 'auth', 'storage', 'realtime', 'supabase_functions', 'graphql', 'graphql_public', 'pgsodium', 'pgsodium_masks', 'vault', 'net', '_realtime', 'supabase_migrations')
        AND nspname NOT LIKE 'pg_%'
    LOOP
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = schema_name AND table_name = 'feedemand')
           AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = schema_name AND table_name = 'feedemand' AND column_name = 'fineamount') THEN
            -- Step 1: Create FINE demand rows for each existing fine
            EXECUTE format('
                INSERT INTO %I.feedemand (
                    ins_id, inscode, yr_id, stu_id, stuadmno, stuclass, courname,
                    demfeeyear, demfeeterm, demfeetype, feeamount, conamount, paidamount, balancedue, reconbalancedue,
                    duedate, paidstatus, createdby, pay_id, demno, demseqtype, activestatus
                )
                SELECT
                    ins_id, inscode, yr_id, stu_id, stuadmno, stuclass, courname,
                    demfeeyear, demfeeterm, ''FINE'', fineamount, 0, fineamount, 0, 0,
                    duedate, ''P'', createdby, pay_id, ''FN'' || dem_id, ''FINE'', 1
                FROM %I.feedemand
                WHERE COALESCE(fineamount, 0) > 0
                  AND demfeetype <> ''FINE''
                  AND NOT EXISTS (
                    SELECT 1 FROM %I.feedemand fd2
                    WHERE fd2.demfeetype = ''FINE''
                    AND fd2.pay_id = %I.feedemand.pay_id
                    AND fd2.stu_id = %I.feedemand.stu_id
                  )
            ', schema_name, schema_name, schema_name, schema_name, schema_name);

            -- Step 2: Update existing demands to remove fine from paidamount and reset fineamount
            EXECUTE format('
                UPDATE %I.feedemand
                SET paidamount = paidamount - fineamount, fineamount = 0
                WHERE COALESCE(fineamount, 0) > 0 AND demfeetype <> ''FINE''
            ', schema_name);

            RAISE NOTICE 'Migrated fines in schema: %', schema_name;
        END IF;
    END LOOP;
END $$;
