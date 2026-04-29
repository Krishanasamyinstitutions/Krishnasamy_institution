-- Idempotent seed for integration_test scenarios.
-- Run against a STAGING Supabase project (never production).
--
-- Creates one institution (KCET), one academic year, one admin user,
-- one accountant, one student, and three fee demands with mixed
-- recon status so cash-payment, reconciliation, and report scenarios
-- have known input.
--
-- Usage (psql):
--   set PGPASSWORD=<staging-db-password>
--   psql -h db.<staging-ref>.supabase.co -U postgres -d postgres ^
--        -f test_data/test_seed.sql

BEGIN;

-- ---------------------------------------------------------------------------
-- Institution
-- ---------------------------------------------------------------------------
INSERT INTO public.institution (ins_id, insname, inshortname, insaddress)
VALUES (1, 'KCET Test Institute', 'kcettest', 'Udumalpet')
ON CONFLICT (ins_id) DO UPDATE
   SET insname = EXCLUDED.insname,
       inshortname = EXCLUDED.inshortname;

-- Academic year
INSERT INTO public.institutionyear (iyr_id, ins_id, yrlabel, iyrstadate, iyrenddate, activestatus)
VALUES (1, 1, '2026-2027', '2026-04-01', '2027-03-31', 1)
ON CONFLICT (iyr_id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Admin user (login: test-admin@kcet.local / Test@2026)
-- ---------------------------------------------------------------------------
INSERT INTO public.institutionusers (
    use_id, ins_id, inscode, usename, usemail, usephone,
    usepassword, urname, desname, ur_id, des_id, activestatus
)
VALUES (
    9001, 1, 'kcettest', 'Test Admin',
    'test-admin@kcet.local', '9000000001',
    'Test@2026', 'Admin', 'Principal', 2, 2, 1
)
ON CONFLICT (use_id) DO UPDATE
   SET usepassword = EXCLUDED.usepassword,
       activestatus = 1;

-- Accountant (login: test-accountant@kcet.local / Test@2026)
INSERT INTO public.institutionusers (
    use_id, ins_id, inscode, usename, usemail, usephone,
    usepassword, urname, desname, ur_id, des_id, activestatus
)
VALUES (
    9002, 1, 'kcettest', 'Test Accountant',
    'test-accountant@kcet.local', '9000000002',
    'Test@2026', 'Accountant', 'Accountant', 3, 3, 1
)
ON CONFLICT (use_id) DO UPDATE
   SET usepassword = EXCLUDED.usepassword,
       activestatus = 1;

COMMIT;

-- ---------------------------------------------------------------------------
-- Tenant-schema seed: one student + 3 demands.
-- Replace `kcettest20262027` with the actual tenant schema if your
-- naming convention differs.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_schema text := 'kcettest20262027';
BEGIN
    -- Skip if schema doesn't exist yet (institution onboarding hasn't run).
    PERFORM 1 FROM information_schema.schemata WHERE schema_name = v_schema;
    IF NOT FOUND THEN
        RAISE NOTICE 'Schema % missing; run institution onboarding first', v_schema;
        RETURN;
    END IF;

    -- Test student (admission no 9999).
    EXECUTE format($f$
        INSERT INTO %I.students (
            stu_id, ins_id, inscode, stuadmno, stuname, stuclass, courname,
            stumobile, stugender, stustadate, activestatus
        )
        VALUES (
            999001, 1, 'kcettest', '9999', 'TEST STUDENT', 'I Year', 'BA-ENG',
            '9000099999', 'M', '2026-04-01', 1
        )
        ON CONFLICT (stu_id) DO UPDATE SET activestatus = 1
    $f$, v_schema);

    -- Pending demand 1: SCHOOL FEES — cash-payable
    EXECUTE format($f$
        INSERT INTO %I.feedemand (
            dem_id, ins_id, inscode, yr_id, stu_id, stuadmno, stuclass,
            demfeeyear, demfeeterm, demfeetype, feeamount, conamount,
            paidamount, balancedue, reconbalancedue, duedate,
            paidstatus, activestatus, createdby, courname
        )
        VALUES (
            999101, 1, 'kcettest', 1, 999001, '9999', 'I Year',
            '2026-2027', 'I SEMESTER', 'SCHOOL FEES', 5000, 0,
            0, 5000, 5000, '2026-04-30',
            'U', 1, 'Test Admin', 'BA-ENG'
        )
        ON CONFLICT (dem_id) DO UPDATE
           SET paidamount = 0,
               balancedue = 5000,
               reconbalancedue = 5000,
               paidstatus = 'U',
               activestatus = 1
    $f$, v_schema);

    -- Demand 2: BOOK FEES — already paid + reconciled (for ledger asserts)
    EXECUTE format($f$
        INSERT INTO %I.feedemand (
            dem_id, ins_id, inscode, yr_id, stu_id, stuadmno, stuclass,
            demfeeyear, demfeeterm, demfeetype, feeamount, conamount,
            paidamount, balancedue, reconbalancedue, duedate,
            paidstatus, activestatus, createdby, courname
        )
        VALUES (
            999102, 1, 'kcettest', 1, 999001, '9999', 'I Year',
            '2026-2027', 'I SEMESTER', 'BOOK FEES', 1500, 0,
            1500, 0, 0, '2026-04-15',
            'P', 1, 'Test Admin', 'BA-ENG'
        )
        ON CONFLICT (dem_id) DO UPDATE
           SET paidamount = 1500,
               balancedue = 0,
               reconbalancedue = 0,
               paidstatus = 'P',
               activestatus = 1
    $f$, v_schema);

    -- Demand 3: VAN FEES — paid but NOT yet reconciled (recon test)
    EXECUTE format($f$
        INSERT INTO %I.feedemand (
            dem_id, ins_id, inscode, yr_id, stu_id, stuadmno, stuclass,
            demfeeyear, demfeeterm, demfeetype, feeamount, conamount,
            paidamount, balancedue, reconbalancedue, duedate,
            paidstatus, activestatus, createdby, courname
        )
        VALUES (
            999103, 1, 'kcettest', 1, 999001, '9999', 'I Year',
            '2026-2027', 'JUNE', 'VAN FEES', 950, 0,
            950, 0, 950, '2026-06-30',
            'P', 1, 'Test Admin', 'BA-ENG'
        )
        ON CONFLICT (dem_id) DO UPDATE
           SET paidamount = 950,
               balancedue = 0,
               reconbalancedue = 950,
               paidstatus = 'P',
               activestatus = 1
    $f$, v_schema);

    RAISE NOTICE 'Test seed applied to %', v_schema;
END $$;
