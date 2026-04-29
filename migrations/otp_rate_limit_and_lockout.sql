-- Hardens the password-reset OTP flow against brute-force and replay.
-- Original migration (`password_reset_otp.sql`) gives a 10-min expiry but:
--   * Allows unlimited verify attempts on the same OTP (brute-force).
--   * Allows verify to leave the OTP usable even after `complete_password_reset`
--     fails — until expiry the same OTP can keep being tried.
--   * No throttle on OTP requests, so a single account could be spammed
--     with SMS to exhaust the BulkSMSGateway credit.
--
-- This migration adds:
--   1. mobotp_attempts (smallint) — wrong-OTP counter, locks out after 5.
--   2. mobotp_request_count + mobotp_window_start — rolling-hour throttle
--      capped at 5 OTP requests per user per hour.
--   3. Verify clears the OTP and sets useotpstatus=1 atomically; the OTP
--      can no longer be replayed even before `complete_password_reset`.
--   4. start_password_reset_otp() RPC the edge function calls before
--      generating an OTP — atomically applies the rate-limit and returns
--      the masked phone if allowed, or NULL if rate-limited.

ALTER TABLE public.institutionusers
    ADD COLUMN IF NOT EXISTS mobotp_attempts      smallint   DEFAULT 0,
    ADD COLUMN IF NOT EXISTS mobotp_request_count smallint   DEFAULT 0,
    ADD COLUMN IF NOT EXISTS mobotp_window_start  timestamptz;

-- ---------------------------------------------------------------------------
-- start_password_reset_otp(p_email)
--   Called by the edge function BEFORE generating an OTP. Returns the
--   masked phone when the user is allowed to receive an OTP, else NULL.
--   Throttle: max 5 OTP requests per user per rolling hour.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.start_password_reset_otp(
    p_email text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_user RECORD;
    v_now  timestamptz := now();
BEGIN
    IF p_email IS NULL OR TRIM(p_email) = '' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'missing_email');
    END IF;

    SELECT use_id, usephone, mobotp_request_count, mobotp_window_start
      INTO v_user
      FROM public.institutionusers
     WHERE LOWER(usemail) = LOWER(TRIM(p_email))
       AND activestatus = 1
     LIMIT 1;

    IF v_user IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'no_user');
    END IF;

    -- Reset the rolling window if the last OTP was > 1 hour ago.
    IF v_user.mobotp_window_start IS NULL
       OR v_user.mobotp_window_start < v_now - interval '1 hour' THEN
        UPDATE public.institutionusers
           SET mobotp_request_count = 1,
               mobotp_window_start  = v_now
         WHERE use_id = v_user.use_id;
    ELSIF v_user.mobotp_request_count >= 5 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'rate_limited',
                                  'retry_after_minutes', 60);
    ELSE
        UPDATE public.institutionusers
           SET mobotp_request_count = mobotp_request_count + 1
         WHERE use_id = v_user.use_id;
    END IF;

    RETURN jsonb_build_object(
        'ok', true,
        'use_id', v_user.use_id,
        'masked_phone',
            CASE WHEN v_user.usephone IS NULL OR LENGTH(v_user.usephone) < 4 THEN ''
                 ELSE REPEAT('*', LENGTH(v_user.usephone) - 4)
                      || RIGHT(v_user.usephone, 4)
            END
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.start_password_reset_otp(text)
    TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- verify_password_reset_otp — REPLACES the original. Adds:
--   * Lockout after 5 wrong attempts (mobotp_attempts).
--   * Atomically clears the OTP on success so it can't be replayed.
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

    SELECT use_id, usemobotp, mobotp_at, mobotp_attempts INTO v_user
      FROM public.institutionusers
     WHERE LOWER(usemail) = LOWER(TRIM(p_email))
       AND activestatus = 1
     LIMIT 1;

    IF v_user IS NULL THEN RETURN false; END IF;

    -- Already locked out for this OTP issuance.
    IF v_user.mobotp_attempts IS NOT NULL AND v_user.mobotp_attempts >= 5 THEN
        RETURN false;
    END IF;

    -- Expired or no OTP on file.
    IF v_user.mobotp_at IS NULL
       OR v_user.mobotp_at < now() - interval '10 minutes'
       OR v_user.usemobotp IS NULL THEN
        RETURN false;
    END IF;

    -- Wrong OTP — increment the attempt counter, return false.
    IF v_user.usemobotp::int <> p_otp THEN
        UPDATE public.institutionusers
           SET mobotp_attempts = COALESCE(mobotp_attempts, 0) + 1
         WHERE use_id = v_user.use_id;
        RETURN false;
    END IF;

    -- Success: mark verified, clear the OTP so it can't be reused even
    -- if the client never reaches `complete_password_reset`.
    UPDATE public.institutionusers
       SET useotpstatus    = 1,
           usemobotp       = NULL,
           mobotp_attempts = 0
     WHERE use_id = v_user.use_id;
    RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.verify_password_reset_otp(text, integer)
    TO anon, authenticated;
