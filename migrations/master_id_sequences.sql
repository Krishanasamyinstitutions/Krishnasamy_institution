-- Convert master-table ID columns to proper auto-increment sequences.
--
-- Before: the existing BEFORE-INSERT triggers used
--     NEW.x_id := COALESCE((SELECT MAX(x_id) FROM t), 0) + 1;
-- which is NOT concurrency-safe — two parallel inserts both compute
-- the same next id and one of them fails with a PK conflict. Also, the
-- concessioncategory trigger overwrites the id even when the caller
-- supplied one, so explicit-id imports (e.g. migrating master data from
-- a legacy system) silently lose their chosen ids.
--
-- After: each affected table gets a real SEQUENCE aligned with MAX(id)+1,
-- and the trigger only assigns nextval() when NEW.x_id is NULL or 0.
-- Imports that set an explicit id pass straight through.
--
-- Tables fixed (across every per-institution schema):
--   feegroup, feetype, concessioncategory, course, class
-- classfeedemand already uses a sequence — left alone.
-- The trigger name and the schema-discovery loop are idempotent, so this
-- migration can be re-run safely.

DO $mig$
DECLARE
    rec RECORD;
BEGIN
    -- Every per-institution schema has a feegroup table. Use that as the
    -- discriminator so we only loop over real tenant schemas (never public,
    -- pg_catalog, storage, etc.).
    FOR rec IN
        SELECT table_schema AS s
        FROM information_schema.tables
        WHERE table_name = 'feegroup'
          AND table_schema NOT IN ('public','pg_catalog','information_schema','storage','auth','realtime','supabase_functions','extensions')
    LOOP
        -- feegroup ---------------------------------------------------------
        EXECUTE format('CREATE SEQUENCE IF NOT EXISTS %I.feegroup_fg_id_seq', rec.s);
        EXECUTE format($q$SELECT setval('%I.feegroup_fg_id_seq', GREATEST(COALESCE((SELECT MAX(fg_id) FROM %I.feegroup), 0), 1), true)$q$, rec.s, rec.s);
        EXECUTE format($q$
            CREATE OR REPLACE FUNCTION %I.set_fg_id() RETURNS trigger LANGUAGE plpgsql AS $t$
            BEGIN
                IF NEW.fg_id IS NULL OR NEW.fg_id = 0 THEN
                    NEW.fg_id := nextval('%I.feegroup_fg_id_seq');
                END IF;
                RETURN NEW;
            END;
            $t$
        $q$, rec.s, rec.s);
        EXECUTE format('DROP TRIGGER IF EXISTS trg_feegroup_fg_id ON %I.feegroup', rec.s);
        EXECUTE format('CREATE TRIGGER trg_feegroup_fg_id BEFORE INSERT ON %I.feegroup FOR EACH ROW EXECUTE FUNCTION %I.set_fg_id()', rec.s, rec.s);

        -- feetype ----------------------------------------------------------
        EXECUTE format('CREATE SEQUENCE IF NOT EXISTS %I.feetype_fee_id_seq', rec.s);
        EXECUTE format($q$SELECT setval('%I.feetype_fee_id_seq', GREATEST(COALESCE((SELECT MAX(fee_id) FROM %I.feetype), 0), 1), true)$q$, rec.s, rec.s);
        EXECUTE format($q$
            CREATE OR REPLACE FUNCTION %I.set_fee_id() RETURNS trigger LANGUAGE plpgsql AS $t$
            BEGIN
                IF NEW.fee_id IS NULL OR NEW.fee_id = 0 THEN
                    NEW.fee_id := nextval('%I.feetype_fee_id_seq');
                END IF;
                RETURN NEW;
            END;
            $t$
        $q$, rec.s, rec.s);
        EXECUTE format('DROP TRIGGER IF EXISTS trg_feetype_fee_id ON %I.feetype', rec.s);
        EXECUTE format('CREATE TRIGGER trg_feetype_fee_id BEFORE INSERT ON %I.feetype FOR EACH ROW EXECUTE FUNCTION %I.set_fee_id()', rec.s, rec.s);

        -- concessioncategory -----------------------------------------------
        -- Also removes the "always override" bug so imports can pin the id.
        EXECUTE format('CREATE SEQUENCE IF NOT EXISTS %I.concessioncategory_con_id_seq', rec.s);
        EXECUTE format($q$SELECT setval('%I.concessioncategory_con_id_seq', GREATEST(COALESCE((SELECT MAX(con_id) FROM %I.concessioncategory), 0), 1), true)$q$, rec.s, rec.s);
        EXECUTE format($q$
            CREATE OR REPLACE FUNCTION %I.set_con_id() RETURNS trigger LANGUAGE plpgsql AS $t$
            BEGIN
                IF NEW.con_id IS NULL OR NEW.con_id = 0 THEN
                    NEW.con_id := nextval('%I.concessioncategory_con_id_seq');
                END IF;
                RETURN NEW;
            END;
            $t$
        $q$, rec.s, rec.s);
        EXECUTE format('DROP TRIGGER IF EXISTS trg_concession_con_id ON %I.concessioncategory', rec.s);
        EXECUTE format('CREATE TRIGGER trg_concession_con_id BEFORE INSERT ON %I.concessioncategory FOR EACH ROW EXECUTE FUNCTION %I.set_con_id()', rec.s, rec.s);

        -- course -----------------------------------------------------------
        EXECUTE format('CREATE SEQUENCE IF NOT EXISTS %I.course_cour_id_seq', rec.s);
        EXECUTE format($q$SELECT setval('%I.course_cour_id_seq', GREATEST(COALESCE((SELECT MAX(cour_id) FROM %I.course), 0), 1), true)$q$, rec.s, rec.s);
        EXECUTE format($q$
            CREATE OR REPLACE FUNCTION %I.set_cour_id() RETURNS trigger LANGUAGE plpgsql AS $t$
            BEGIN
                IF NEW.cour_id IS NULL OR NEW.cour_id = 0 THEN
                    NEW.cour_id := nextval('%I.course_cour_id_seq');
                END IF;
                RETURN NEW;
            END;
            $t$
        $q$, rec.s, rec.s);
        EXECUTE format('DROP TRIGGER IF EXISTS trg_course_cour_id ON %I.course', rec.s);
        EXECUTE format('CREATE TRIGGER trg_course_cour_id BEFORE INSERT ON %I.course FOR EACH ROW EXECUTE FUNCTION %I.set_cour_id()', rec.s, rec.s);

        -- class ------------------------------------------------------------
        EXECUTE format('CREATE SEQUENCE IF NOT EXISTS %I.class_cla_id_seq', rec.s);
        EXECUTE format($q$SELECT setval('%I.class_cla_id_seq', GREATEST(COALESCE((SELECT MAX(cla_id) FROM %I.class), 0), 1), true)$q$, rec.s, rec.s);
        EXECUTE format($q$
            CREATE OR REPLACE FUNCTION %I.set_cla_id() RETURNS trigger LANGUAGE plpgsql AS $t$
            BEGIN
                IF NEW.cla_id IS NULL OR NEW.cla_id = 0 THEN
                    NEW.cla_id := nextval('%I.class_cla_id_seq');
                END IF;
                RETURN NEW;
            END;
            $t$
        $q$, rec.s, rec.s);
        EXECUTE format('DROP TRIGGER IF EXISTS trg_class_cla_id ON %I.class', rec.s);
        EXECUTE format('CREATE TRIGGER trg_class_cla_id BEFORE INSERT ON %I.class FOR EACH ROW EXECUTE FUNCTION %I.set_cla_id()', rec.s, rec.s);

        RAISE NOTICE 'Master-id sequences installed for schema: %', rec.s;
    END LOOP;
END;
$mig$;
