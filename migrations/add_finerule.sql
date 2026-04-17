-- Add fineamount column to feedemand and create finerule table (ALL SCHEMAS)
-- Run this once in Supabase SQL editor

DO $$
DECLARE
    schema_name TEXT;
BEGIN
    FOR schema_name IN
        SELECT nspname FROM pg_namespace
        WHERE nspname NOT IN ('public', 'pg_catalog', 'information_schema', 'pg_toast', 'extensions', 'auth', 'storage', 'realtime', 'supabase_functions', 'graphql', 'graphql_public', 'pgsodium', 'pgsodium_masks', 'vault', 'net', '_realtime', 'supabase_migrations')
        AND nspname NOT LIKE 'pg_%'
    LOOP
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = schema_name AND table_name = 'feedemand') THEN
            -- Add fineamount column to feedemand
            EXECUTE format('ALTER TABLE %I.feedemand ADD COLUMN IF NOT EXISTS fineamount NUMERIC(12,2) DEFAULT 0', schema_name);

            -- Create finerule table
            IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = schema_name AND table_name = 'finerule') THEN
                EXECUTE format('CREATE TABLE %I.finerule (fr_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY, ins_id integer NOT NULL, rulename varchar(50) NOT NULL, feetype varchar(30) DEFAULT ''ALL'', from_days integer NOT NULL, to_days integer, fine_type varchar(10) DEFAULT ''FIXED'' CHECK (fine_type IN (''FIXED'',''PERCENT'')), fine_value numeric(12,2) NOT NULL, activestatus smallint DEFAULT 1 NOT NULL, createdat timestamp DEFAULT now(), createdby varchar(50))', schema_name);

                -- Grant permissions
                EXECUTE format('GRANT ALL ON %I.finerule TO anon, authenticated', schema_name);
            END IF;

            RAISE NOTICE 'Updated schema: %', schema_name;
        END IF;
    END LOOP;
END $$;
