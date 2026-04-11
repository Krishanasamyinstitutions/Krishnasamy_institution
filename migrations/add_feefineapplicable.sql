-- Add feefineapplicable column to feetype across all institution schemas.
-- Idempotent — safe to re-run.

DO $$
DECLARE
    schema_name TEXT;
BEGIN
    FOR schema_name IN
        SELECT nspname FROM pg_namespace
        WHERE nspname NOT IN ('public', 'pg_catalog', 'information_schema', 'pg_toast', 'extensions', 'auth', 'storage', 'realtime', 'supabase_functions', 'graphql', 'graphql_public', 'pgsodium', 'pgsodium_masks', 'vault', 'net', '_realtime', 'supabase_migrations')
        AND nspname NOT LIKE 'pg_%'
    LOOP
        IF EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_schema = schema_name AND table_name = 'feetype') THEN
            EXECUTE format('ALTER TABLE %I.feetype ADD COLUMN IF NOT EXISTS feefineapplicable smallint DEFAULT 0', schema_name);
            RAISE NOTICE 'Added feefineapplicable to schema: %', schema_name;
        END IF;
    END LOOP;
END $$;
