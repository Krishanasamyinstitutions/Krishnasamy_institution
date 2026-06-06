-- ============================================================================
-- Allow client-side UPDATE on public.institutionusers (terminate / suspend).
-- ============================================================================
-- The User Creation screen terminates a staff/accountant by updating
-- public.institutionusers (activestatus = 9, terminatedby/date/reason). RLS is
-- enabled on the table and SELECT/INSERT are permitted, but there is no
-- permissive UPDATE policy, so the client UPDATE fails with:
--   "new row violates row-level security policy" (SQLSTATE 42501).
-- Password-reset paths update this table only inside SECURITY DEFINER functions
-- (which bypass RLS), so they were unaffected.
--
-- This adds a permissive UPDATE policy — consistent with the existing
-- permissive posture (app-level auth, not RLS-enforced). Safe / idempotent.
-- ============================================================================

ALTER TABLE public.institutionusers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "institutionusers_update_all" ON public.institutionusers;
CREATE POLICY "institutionusers_update_all"
  ON public.institutionusers
  FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

NOTIFY pgrst, 'reload config';
