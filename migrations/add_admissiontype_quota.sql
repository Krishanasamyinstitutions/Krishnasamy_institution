-- Add admissiontype, quota tables and admname, quoname columns to students
-- Runs across all per-institution schemas

DO $$
DECLARE
    schema_name TEXT;
BEGIN
    FOR schema_name IN
        SELECT DISTINCT table_schema FROM information_schema.tables
        WHERE table_name = 'students' AND table_schema NOT IN ('public', 'pg_catalog', 'information_schema')
    LOOP
        -- admissiontype table (no auto-id; caller supplies adm_id)
        EXECUTE format($f$
            CREATE TABLE IF NOT EXISTS %I.admissiontype (
                adm_id SMALLINT PRIMARY KEY,
                admname VARCHAR(30) NOT NULL,
                ins_id INTEGER,
                activestatus SMALLINT DEFAULT 1 NOT NULL,
                createdat TIMESTAMP DEFAULT now(),
                createdby VARCHAR(50)
            )
        $f$, schema_name);
        EXECUTE format('GRANT ALL ON %I.admissiontype TO anon, authenticated', schema_name);

        -- quota table (no auto-id; caller supplies quo_id)
        EXECUTE format($f$
            CREATE TABLE IF NOT EXISTS %I.quota (
                quo_id SMALLINT PRIMARY KEY,
                quoname VARCHAR(30) NOT NULL,
                ins_id INTEGER,
                activestatus SMALLINT DEFAULT 1 NOT NULL,
                createdat TIMESTAMP DEFAULT now(),
                createdby VARCHAR(50)
            )
        $f$, schema_name);
        EXECUTE format('GRANT ALL ON %I.quota TO anon, authenticated', schema_name);

        -- students.admname, students.quoname columns
        EXECUTE format('ALTER TABLE %I.students ADD COLUMN IF NOT EXISTS admname VARCHAR(30)', schema_name);
        EXECUTE format('ALTER TABLE %I.students ADD COLUMN IF NOT EXISTS quoname VARCHAR(30)', schema_name);

        RAISE NOTICE 'Updated schema: %', schema_name;
    END LOOP;
END $$;
