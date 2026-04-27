-- Per-institution student photo buckets.
--
-- Changes the shared `student-photos` bucket to one bucket per
-- institution, named `student-photos-<inscode>`. Benefits:
--   * Separate Supabase storage quotas per school.
--   * Deletion of an institution cleans up its photos by dropping the
--     whole bucket — no stray files left behind.
--   * Ready for Supabase Auth: once JWTs are in place, per-bucket RLS
--     can restrict reads to a matching `ins_id` claim.
--
-- Until Auth is added, the buckets are still `public=true` so existing
-- flows keep working. Anyone with a URL can still read it; true
-- cross-institution privacy requires JWT-based RLS (Audit item #2).
--
-- Also installs a helper RPC so the app can create the right bucket at
-- institution registration time without needing storage admin rights.

-- ---------------------------------------------------------------------------
-- Helper: create one bucket + read/write policies for an inscode.
-- Idempotent — safe to re-run.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ensure_student_photo_bucket(p_inscode text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_bucket text;
    v_code   text;
BEGIN
    IF p_inscode IS NULL OR TRIM(p_inscode) = '' THEN
        RAISE EXCEPTION 'inscode required';
    END IF;
    v_code := lower(TRIM(p_inscode));
    v_bucket := 'student-photos-' || v_code;

    INSERT INTO storage.buckets (id, name, public)
    VALUES (v_bucket, v_bucket, true)
    ON CONFLICT (id) DO UPDATE SET public = true;

    -- Policy names include the bucket id so each bucket gets its own row;
    -- without this the second INSERT would hit the same policy name.
    EXECUTE format($p$ DROP POLICY IF EXISTS %I ON storage.objects $p$,
        v_bucket || ' public read');
    EXECUTE format($p$
        CREATE POLICY %I
        ON storage.objects FOR SELECT TO public
        USING (bucket_id = %L)
    $p$, v_bucket || ' public read', v_bucket);

    EXECUTE format($p$ DROP POLICY IF EXISTS %I ON storage.objects $p$,
        v_bucket || ' anon insert');
    EXECUTE format($p$
        CREATE POLICY %I
        ON storage.objects FOR INSERT TO anon, authenticated
        WITH CHECK (bucket_id = %L)
    $p$, v_bucket || ' anon insert', v_bucket);

    EXECUTE format($p$ DROP POLICY IF EXISTS %I ON storage.objects $p$,
        v_bucket || ' anon update');
    EXECUTE format($p$
        CREATE POLICY %I
        ON storage.objects FOR UPDATE TO anon, authenticated
        USING (bucket_id = %L)
        WITH CHECK (bucket_id = %L)
    $p$, v_bucket || ' anon update', v_bucket, v_bucket);

    EXECUTE format($p$ DROP POLICY IF EXISTS %I ON storage.objects $p$,
        v_bucket || ' anon delete');
    EXECUTE format($p$
        CREATE POLICY %I
        ON storage.objects FOR DELETE TO anon, authenticated
        USING (bucket_id = %L)
    $p$, v_bucket || ' anon delete', v_bucket);

    RETURN v_bucket;
END;
$$;

GRANT EXECUTE ON FUNCTION public.ensure_student_photo_bucket(text)
    TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- Back-fill: create a bucket for each existing institution.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT inscode FROM public.institution WHERE activestatus = 1 LOOP
        PERFORM public.ensure_student_photo_bucket(rec.inscode);
    END LOOP;
END $$;
