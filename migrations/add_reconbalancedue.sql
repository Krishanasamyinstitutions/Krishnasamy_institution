-- Add reconbalancedue column to feedemand table (ALL SCHEMAS)
-- This column tracks the "reconciled" balance - only updated after bank reconciliation approval
-- Default: same as feeamount (full pending amount until reconciled)
-- Run this once in Supabase SQL editor - it auto-detects all schemas with feedemand table

DO $$
DECLARE
    schema_name TEXT;
BEGIN
    FOR schema_name IN
        SELECT nspname FROM pg_namespace
        WHERE nspname NOT IN ('public', 'pg_catalog', 'information_schema', 'pg_toast', 'extensions', 'auth', 'storage', 'realtime', 'supabase_functions', 'graphql', 'graphql_public', 'pgsodium', 'pgsodium_masks', 'vault', 'net', '_realtime', 'supabase_migrations')
        AND nspname NOT LIKE 'pg_%'
    LOOP
        -- Check if feedemand table exists in this schema
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = schema_name AND table_name = 'feedemand') THEN
            -- Step 1: Add column
            EXECUTE format('ALTER TABLE %I.feedemand ADD COLUMN IF NOT EXISTS reconbalancedue NUMERIC(12,2) DEFAULT 0', schema_name);

            -- Step 2: Initialize with feeamount
            EXECUTE format('UPDATE %I.feedemand SET reconbalancedue = feeamount WHERE reconbalancedue = 0 OR reconbalancedue IS NULL', schema_name);

            -- Step 3: Sync already reconciled payments
            EXECUTE format('UPDATE %I.feedemand fd SET reconbalancedue = fd.balancedue FROM %I.payment p WHERE fd.pay_id = p.pay_id AND p.recon_status = ''R'' AND fd.activestatus = 1', schema_name, schema_name);

            -- Step 4: Update trigger to include reconbalancedue on fee demand approval
            EXECUTE format('CREATE OR REPLACE FUNCTION %I.fn_approve_tempfeedemand() RETURNS trigger LANGUAGE plpgsql AS $t$ BEGIN IF NEW.isapproved = true AND (OLD.isapproved = false OR OLD.isapproved IS NULL) THEN INSERT INTO %I.feedemand (ins_id, inscode, yr_id, stu_id, stuadmno, stuclass, courname, demfeeyear, demfeeterm, demfeetype, feeamount, con_id, conamount, balancedue, reconbalancedue, duedate, activestatus, createdat, createdby, paidstatus, paidamount) VALUES (NEW.ins_id, NEW.inscode, NEW.yr_id, NEW.stu_id, NEW.stuadmno, NEW.stuclass, NEW.courname, NEW.demfeeyear, NEW.demfeeterm, NEW.demfeetype, NEW.feeamount, NEW.con_id, NEW.conamount, NEW.balancedue, NEW.feeamount, NEW.duedate, 1, NEW.createdat, NEW.createdby, ''U'', 0); NEW.activestatus := 9; END IF; RETURN NEW; END; $t$', schema_name, schema_name);

            RAISE NOTICE 'Updated schema: %', schema_name;
        END IF;
    END LOOP;
END $$;
