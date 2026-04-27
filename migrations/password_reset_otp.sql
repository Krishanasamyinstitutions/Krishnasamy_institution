-- Mobile-OTP password reset for institutionusers (admin/staff/accountant).
-- Pairs with the supabase/functions/send-password-reset-otp Edge Function:
--   1. Edge function generates the OTP, stores it in usemobotp +
--      mobotp_at, calls BulkSMSGateway. Service-role key, so policies
--      don't matter.
--   2. Client calls verify_password_reset_otp with email + OTP. Marks
--      useotpstatus = 1 if the OTP is correct AND fresh (within 10 min).
--   3. Client calls complete_password_reset with email + new password.
--      The hash_user_password_trigger auto-hashes the plaintext.
--
-- The existing usemobotp + useotpstatus columns already exist; we only
-- add a timestamp column so we can enforce a 10-minute expiry window
-- (otherwise an OTP intercepted last week could still reset a password).

ALTER TABLE public.institutionusers
    ADD COLUMN IF NOT EXISTS mobotp_at timestamptz;

-- ---------------------------------------------------------------------------
-- verify_password_reset_otp: returns true when the OTP matches AND was
-- issued within the last 10 minutes. Side effect: sets useotpstatus = 1
-- so a subsequent complete_password_reset call is gated by it.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.verify_password_reset_otp(
    p_email text,
    p_otp   integer
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_user RECORD;
BEGIN
    IF p_email IS NULL OR TRIM(p_email) = '' OR p_otp IS NULL THEN
        RETURN false;
    END IF;
    SELECT use_id, usemobotp, mobotp_at INTO v_user
    FROM public.institutionusers
    WHERE LOWER(usemail) = LOWER(TRIM(p_email))
      AND activestatus = 1
    LIMIT 1;
    IF v_user IS NULL THEN RETURN false; END IF;
    IF v_user.usemobotp IS NULL OR v_user.usemobotp::int <> p_otp THEN RETURN false; END IF;
    IF v_user.mobotp_at IS NULL OR v_user.mobotp_at < now() - interval '10 minutes' THEN
        RETURN false;
    END IF;
    UPDATE public.institutionusers
       SET useotpstatus = 1
     WHERE use_id = v_user.use_id;
    RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.verify_password_reset_otp(text, integer)
    TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- complete_password_reset: gated by useotpstatus = 1 set by the verify
-- step. Writes the new plaintext into usepassword — the existing
-- hash_user_password_trigger hashes it before storage. Clears OTP state
-- so the same OTP can't be reused.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.complete_password_reset(
    p_email        text,
    p_new_password text
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_user RECORD;
BEGIN
    IF p_email IS NULL OR TRIM(p_email) = ''
       OR p_new_password IS NULL OR LENGTH(p_new_password) < 6 THEN
        RETURN false;
    END IF;
    SELECT use_id, useotpstatus INTO v_user
    FROM public.institutionusers
    WHERE LOWER(usemail) = LOWER(TRIM(p_email))
      AND activestatus = 1
    LIMIT 1;
    IF v_user IS NULL OR v_user.useotpstatus <> 1 THEN
        RETURN false;
    END IF;
    UPDATE public.institutionusers
       SET usepassword  = p_new_password,
           usemobotp    = NULL,
           mobotp_at    = NULL,
           useotpstatus = 0
     WHERE use_id = v_user.use_id;
    RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.complete_password_reset(text, text)
    TO anon, authenticated;
