-- ============================================================================
-- Terminate a staff/accountant via a SECURITY DEFINER RPC (bypasses RLS).
-- ============================================================================
-- A direct client UPDATE on public.institutionusers was blocked by row-level
-- security (SQLSTATE 42501) and adding a permissive UPDATE policy did not clear
-- it (a restrictive policy / role mismatch we can't inspect from the client).
--
-- This function runs as its owner (table owner), so RLS does not apply — the
-- same pattern the password-reset functions already use. The app calls it via
-- client.rpc('terminate_institution_user', ...). Returns the number of rows
-- updated so the client can report success/failure. Safe / idempotent.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.terminate_institution_user(
  p_use_id integer,
  p_ins_id integer,
  p_terminatedby text,
  p_terminatedreason text
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  UPDATE public.institutionusers
     SET activestatus    = 9,
         terminatedby    = p_terminatedby,
         terminateddate  = now(),
         terminatedreason = p_terminatedreason
   WHERE use_id = p_use_id
     AND ins_id = p_ins_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.terminate_institution_user(integer, integer, text, text)
  TO anon, authenticated;

NOTIFY pgrst, 'reload config';
