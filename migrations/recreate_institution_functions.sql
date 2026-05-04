CREATE OR REPLACE FUNCTION public.register_institution(p_insname text, p_inscode text, p_insstadate date, p_insautusername text, p_insdesignation text, p_insmobno text, p_insmail text, p_it_id integer, p_insrecognised character, p_insaffliation text, p_insaffno text, p_insaffstayear text, p_insaddress1 text, p_insaddress2 text, p_insaddress3 text, p_inscity text, p_insstate text, p_inscountry text, p_inspincode text, p_yrlabel text, p_yrstadate date, p_yrenddate date, p_adminname text, p_adminemail text, p_adminphone text, p_adminpassword text, p_admindob date, p_admindesignation text DEFAULT 'Principal'::text, p_inshortname text DEFAULT NULL) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_ins_id int; v_des_id int; v_ur_id int; v_use_id int;
  v_short text; v_schema text;
BEGIN
  -- Validation: required fields must be non-empty
  IF COALESCE(TRIM(p_insname),  '') = '' THEN RAISE EXCEPTION 'Institution name is required'; END IF;
  IF COALESCE(TRIM(p_inscode),  '') = '' THEN RAISE EXCEPTION 'Institution code is required'; END IF;
  IF COALESCE(TRIM(p_insmail),  '') = '' THEN RAISE EXCEPTION 'Institution email is required'; END IF;
  IF COALESCE(TRIM(p_adminname),'') = '' THEN RAISE EXCEPTION 'Admin name is required'; END IF;
  IF COALESCE(TRIM(p_adminemail),'')= '' THEN RAISE EXCEPTION 'Admin email is required'; END IF;
  IF COALESCE(TRIM(p_adminpassword),'')='' THEN RAISE EXCEPTION 'Admin password is required'; END IF;
  IF COALESCE(TRIM(p_yrlabel),  '') = '' THEN RAISE EXCEPTION 'Year label is required'; END IF;

  v_short := lower(COALESCE(NULLIF(TRIM(p_inshortname), ''), TRIM(p_inscode)));
  IF v_short = '' THEN RAISE EXCEPTION 'Institution short name is required'; END IF;

  -- All inserts below happen inside this function's implicit transaction.
  -- If create_institution_schema raises later, every row is rolled back.
  INSERT INTO institution (insname, inscode, inshortname, insstadate, insautusername, insdesignation, insmobno, insmail, it_id, insrecognised, insaffliation, insaffno, insaffstayear, insaddress1, insaddress2, insaddress3, inscity, insstate, inscountry, inspincode, insipaddress, inssername, insserurl, updatedby, activestatus)
  VALUES (p_insname, p_inscode, v_short, p_insstadate, p_insautusername, p_insdesignation, p_insmobno, p_insmail, p_it_id, p_insrecognised, p_insaffliation, p_insaffno, p_insaffstayear, p_insaddress1, p_insaddress2, p_insaddress3, p_inscity, p_insstate, p_inscountry, p_inspincode, '0.0.0.0', 'default', 'default', p_insautusername, 1) RETURNING ins_id INTO v_ins_id;

  INSERT INTO staffdesignation (ins_id, desname, activestatus) VALUES (v_ins_id, p_admindesignation, 1) RETURNING des_id INTO v_des_id;
  INSERT INTO custuserroles (ins_id, inscode, urname, activestatus) VALUES (v_ins_id, p_inscode, 'Admin', 1) RETURNING ur_id INTO v_ur_id;
  INSERT INTO custuserroles (ins_id, inscode, urname, activestatus) VALUES (v_ins_id, p_inscode, 'Accountant', 1);

  INSERT INTO institutionusers (ins_id, inscode, usename, usemail, usephone, usepassword, usestadate, useotpstatus, usedob, ur_id, urname, des_id, desname, userepto, activestatus)
  VALUES (v_ins_id, p_inscode, p_adminname, p_adminemail, p_adminphone, crypt(p_adminpassword, gen_salt('bf', 10)), CURRENT_DATE, 0, p_admindob, v_ur_id, 'Admin', v_des_id, p_admindesignation, 0, 1) RETURNING use_id INTO v_use_id;

  -- Create the institution schema with all tables, triggers, year records.
  -- create_institution_schema handles the institutionyear insert itself
  -- (with ON CONFLICT DO NOTHING against the uq_institutionyear_ins_yr constraint).
  -- If this fails, the function aborts and every insert above is rolled back.
  v_schema := v_short || replace(p_yrlabel, '-', '');
  PERFORM public.create_institution_schema(v_schema, v_ins_id, p_yrlabel, p_yrstadate, p_yrenddate);

  RETURN json_build_object('ins_id', v_ins_id, 'inscode', p_inscode, 'yr_id', 0, 'use_id', v_use_id, 'schema', v_schema);
END; $$;

-- ============================================
-- EXPOSE SCHEMA HELPER (must be before create_institution_schema)
-- ============================================
CREATE OR REPLACE FUNCTION public.expose_schema(p_schema text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE current_schemas text;
BEGIN
  SELECT current_setting('pgrst.db_schemas', true) INTO current_schemas;
  IF current_schemas IS NULL OR current_schemas = '' THEN current_schemas := 'public'; END IF;
  IF position(p_schema in current_schemas) = 0 THEN
    EXECUTE format('ALTER ROLE authenticator SET pgrst.db_schemas = %L', current_schemas || ', ' || p_schema);
    NOTIFY pgrst, 'reload config';
  END IF;
END; $$;

-- Expose every institution schema in one shot. Called from the Flutter app on
-- login as a best-effort sync. On Supabase free tier the ALTER ROLE may fail
-- silently for non-superuser; the per-schema fallback in expose_schema is
-- still useful when permissions allow it.
CREATE OR REPLACE FUNCTION public.expose_all_schemas() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  rec RECORD;
  v_list text := 'public';
BEGIN
  FOR rec IN
    SELECT DISTINCT lower(i.inshortname) || replace(iy.yrlabel, '-', '') AS schema_name
    FROM public.institution i
    JOIN public.institutionyear iy ON iy.ins_id = i.ins_id
    WHERE i.inshortname IS NOT NULL
      AND iy.activestatus = 1
  LOOP
    -- Verify the schema actually exists before adding it
    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = rec.schema_name) THEN
      v_list := v_list || ', ' || rec.schema_name;
    END IF;
  END LOOP;
  BEGIN
    EXECUTE format('ALTER ROLE authenticator SET pgrst.db_schemas = %L', v_list);
    NOTIFY pgrst, 'reload config';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'expose_all_schemas: ALTER ROLE skipped (insufficient privilege): %', SQLERRM;
  END;
END; $$;

-- ============================================
-- SCHEMA CREATION FUNCTION (complete with all triggers)
-- ============================================

CREATE OR REPLACE FUNCTION public.create_institution_schema(
  p_schema_name text,
  p_ins_id integer DEFAULT NULL,
  p_year_label text DEFAULT NULL,
  p_start_date date DEFAULT NULL,
  p_end_date date DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_schema text := lower(p_schema_name); v_inscode varchar(10);
BEGIN
  -- Get inscode for year record
  IF p_ins_id IS NOT NULL THEN
    SELECT inscode INTO v_inscode FROM public.institution WHERE ins_id = p_ins_id;
  END IF;
  EXECUTE format('CREATE SCHEMA IF NOT EXISTS %I', v_schema);

  -- year
  EXECUTE format('CREATE TABLE %I.year (yr_id integer NOT NULL PRIMARY KEY, ins_id integer NOT NULL, yrlabel varchar(9) NOT NULL, yrstadate date NOT NULL, yrenddate date NOT NULL, createdon timestamp DEFAULT now() NOT NULL, activestatus smallint DEFAULT 1 NOT NULL)', v_schema);

  -- students
  EXECUTE format('CREATE TABLE %I.students (stu_id bigint NOT NULL PRIMARY KEY CHECK (stu_id > 0), ins_id integer NOT NULL, inscode varchar(10) NOT NULL, yr_id integer NOT NULL, yrlabel varchar(9) NOT NULL, stuadmno varchar(25) NOT NULL, stuadmdate date NOT NULL, stuname varchar(50) NOT NULL, stugender char(1) NOT NULL CHECK (stugender = ANY(ARRAY[''M'',''F'',''T''])), studob date NOT NULL, stumobile varchar(30), stuemail varchar(254), stuaddress text, stucity varchar(50), stustate varchar(50), stucountry varchar(50), stupin varchar(6), stugeocoordinates varchar(40), stubloodgrp varchar(20), stuphoto text, stuclass varchar(20) NOT NULL, cour_id integer, courname varchar(20), con_id integer, stucondesc varchar(20), stuser_id varchar(25) NOT NULL, stupassword varchar(255), stumobotp numeric(6,0), stuotpstatus smallint DEFAULT 0 NOT NULL, approvedby varchar(50), approveddate timestamp DEFAULT now() NOT NULL, suspendeddate date, suspendedby varchar(50), terminateddate date, terminatedby varchar(50), activestatus smallint DEFAULT 1 NOT NULL CHECK (activestatus = ANY(ARRAY[1,2,9])), createdon timestamp DEFAULT now() NOT NULL, terminatedreason text, batch varchar(9), admname varchar(30), quoname varchar(30), admittyear varchar(9))', v_schema);
  EXECUTE format('ALTER TABLE %I.students ADD CONSTRAINT students_stuemail_key UNIQUE (stuemail)', v_schema);
  EXECUTE format('ALTER TABLE %I.students ADD CONSTRAINT uq_students_admission UNIQUE (ins_id, stuadmno)', v_schema);

  -- parents
  EXECUTE format('CREATE TABLE %I.parents (par_id bigint NOT NULL PRIMARY KEY, yr_id integer NOT NULL, yrlabel varchar(9), partype char(1) NOT NULL CHECK (partype = ANY(ARRAY[''P'',''G''])), paremail varchar(254), fathername varchar(50), mothername varchar(50), guardianname varchar(50), fathermobile varchar(20), mothermobile varchar(20), guardianmobile varchar(20), fatheroccupation varchar(60), motheroccupation varchar(60), guardianoccupation varchar(60), payincharge varchar(50) NOT NULL, payinchargemob varchar(20) NOT NULL, parpassword varchar(255), parmobotp numeric(6,0), parotpstatus smallint DEFAULT 0 NOT NULL, approvedby varchar(50), approveddate timestamp DEFAULT now(), terminateddate date, terminatedby varchar(50), activestatus smallint DEFAULT 1 NOT NULL CHECK (activestatus = ANY(ARRAY[1,2,9])), ins_id integer)', v_schema);
  EXECUTE format('ALTER TABLE %I.parents ADD CONSTRAINT parents_paremail_key UNIQUE (paremail)', v_schema);

  -- parentdetail
  EXECUTE format('CREATE TABLE %I.parentdetail (pd_id bigint NOT NULL PRIMARY KEY, yr_id integer NOT NULL, yrlabel varchar(9), par_id bigint NOT NULL, stu_id bigint NOT NULL, ins_id integer NOT NULL, inscode varchar(10) NOT NULL, stuadmno varchar(20) NOT NULL UNIQUE, stuname varchar(50) NOT NULL, stuclass varchar(20) NOT NULL, activestatus smallint DEFAULT 1 NOT NULL)', v_schema);

  -- feedemand
  EXECUTE format('CREATE TABLE %I.feedemand (dem_id bigint NOT NULL PRIMARY KEY, demno varchar(30) NOT NULL, demseqtype varchar(20) NOT NULL, ins_id integer NOT NULL, inscode varchar(10) NOT NULL, yr_id integer NOT NULL, stu_id bigint, stuadmno varchar(25) NOT NULL, stuclass varchar(20) NOT NULL, demfeeyear varchar(9) NOT NULL, demfeeterm varchar(20) NOT NULL, demfeetype varchar(30) NOT NULL, feeamount numeric(12,2) NOT NULL, con_id integer, conamount numeric(12,2) DEFAULT 0, paidamount numeric(12,2) DEFAULT 0, fineamount numeric(12,2) DEFAULT 0, balancedue numeric(12,2) CHECK (balancedue >= 0), reconbalancedue numeric(12,2) DEFAULT 0, duedate date NOT NULL, pay_id integer, paidstatus char(1) DEFAULT ''U'' NOT NULL CHECK (paidstatus = ANY(ARRAY[''P'',''U''])), createdby varchar(50) NOT NULL, createdat timestamp DEFAULT now() NOT NULL, activestatus smallint DEFAULT 1 NOT NULL CHECK (activestatus = ANY(ARRAY[0,1])), inactivedate timestamp, remarks varchar(50), fee_id integer, courname varchar(20))', v_schema);

  -- tempfeedemand
  EXECUTE format('CREATE TABLE %I.tempfeedemand (temp_id bigint NOT NULL PRIMARY KEY, ins_id integer NOT NULL, inscode varchar(10) NOT NULL, yr_id integer NOT NULL, stu_id bigint, stuadmno varchar(25) NOT NULL, stuclass varchar(20) NOT NULL, courname varchar(20), demfeeyear varchar(9) NOT NULL, demfeeterm varchar(20) NOT NULL, demfeetype varchar(30) NOT NULL, feeamount numeric(12,2) NOT NULL, con_id integer, conamount numeric(12,2) DEFAULT 0, balancedue numeric(12,2), duedate date NOT NULL, activestatus smallint DEFAULT 1 NOT NULL, createdat timestamptz DEFAULT now(), createdby varchar(50), isapproved boolean DEFAULT false)', v_schema);

  -- feegroup
  EXECUTE format('CREATE TABLE %I.feegroup (fg_id integer NOT NULL PRIMARY KEY, fgdesc varchar(30) NOT NULL, ban_id integer, ins_id integer NOT NULL, yr_id integer NOT NULL, yrlabel varchar(9) NOT NULL, activestatus smallint DEFAULT 1 NOT NULL CHECK (activestatus = ANY(ARRAY[0,1,9])))', v_schema);

  -- feetype (feefineapplicable: 1 = fines apply when overdue, 0 = no fine)
  EXECUTE format('CREATE TABLE %I.feetype (fee_id integer NOT NULL PRIMARY KEY, feedesc varchar(30) NOT NULL, feeshort varchar(10) NOT NULL, feefineapplicable smallint DEFAULT 0, fg_id integer NOT NULL, yr_id integer NOT NULL, yrlabel varchar(9) NOT NULL, activestatus smallint DEFAULT 1 NOT NULL CHECK (activestatus = ANY(ARRAY[0,1,9])), ins_id integer)', v_schema);
  EXECUTE format('ALTER TABLE %I.feetype ADD CONSTRAINT fk_feetype_feegroup FOREIGN KEY (fg_id) REFERENCES %I.feegroup(fg_id)', v_schema, v_schema);
  -- Lets PostgREST resolve embedded selects like feedemand?select=*,feetype(*) in the mobile app.
  EXECUTE format('ALTER TABLE %I.feedemand ADD CONSTRAINT fk_feedemand_feetype FOREIGN KEY (fee_id) REFERENCES %I.feetype(fee_id) NOT VALID', v_schema, v_schema);

  -- concessioncategory
  EXECUTE format('CREATE TABLE %I.concessioncategory (con_id integer NOT NULL PRIMARY KEY, condesc varchar(20) NOT NULL, ins_id integer NOT NULL, ordid integer, activestatus smallint DEFAULT 1 NOT NULL CHECK (activestatus = ANY(ARRAY[0,1])))', v_schema);

  -- course
  EXECUTE format('CREATE TABLE %I.course (cour_id integer NOT NULL PRIMARY KEY, courname varchar(100) NOT NULL, ordid smallint, ins_id integer, activestatus smallint DEFAULT 1 NOT NULL)', v_schema);

  -- class
  EXECUTE format('CREATE TABLE %I.class (cla_id integer NOT NULL PRIMARY KEY, claname varchar(20) NOT NULL, ins_id integer, ordid smallint, succeedingclass integer, cour_id integer, activestatus smallint DEFAULT 1 NOT NULL)', v_schema);
  -- succeedingclass is the cla_id of the next class in the promotion ladder
  -- (NULL for the terminal class). cour_id is optional / informational.

  -- admissiontype + quota master lookups (add_admissiontype_quota.sql)
  EXECUTE format('CREATE TABLE %I.admissiontype (adm_id smallint PRIMARY KEY, admname varchar(30) NOT NULL, ins_id integer, activestatus smallint DEFAULT 1 NOT NULL, createdat timestamp DEFAULT now(), createdby varchar(50))', v_schema);
  EXECUTE format('CREATE TABLE %I.quota (quo_id smallint PRIMARY KEY, quoname varchar(30) NOT NULL, ins_id integer, activestatus smallint DEFAULT 1 NOT NULL, createdat timestamp DEFAULT now(), createdby varchar(50))', v_schema);

  -- classfeedemand
  EXECUTE format('CREATE TABLE %I.classfeedemand (cf_id integer NOT NULL PRIMARY KEY, cfclass varchar(20), cfterm varchar(20), cffeetype varchar(30), cfamount numeric(12,2), cfdduedate date, admissiontype smallint)', v_schema);

  -- finerule (overdue fine slabs configured by admin)
  EXECUTE format('CREATE TABLE %I.finerule (fr_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY, ins_id integer NOT NULL, rulename varchar(50) NOT NULL, feetype varchar(30) DEFAULT ''ALL'', from_days integer NOT NULL, to_days integer, fine_type varchar(10) DEFAULT ''FIXED'' CHECK (fine_type IN (''FIXED'',''PERCENT'')), fine_value numeric(12,2) NOT NULL, activestatus smallint DEFAULT 1 NOT NULL, createdat timestamp DEFAULT now(), createdby varchar(50))', v_schema);

  -- challan
  EXECUTE format('CREATE TABLE %I.challan (cha_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, ins_id integer, inscode varchar(10) NOT NULL, yr_id integer, yrlabel varchar(9), stu_id bigint NOT NULL, stuadmno varchar(20) NOT NULL, stuname varchar(50) NOT NULL, chano varchar(25) NOT NULL, fcseqtype varchar(20) NOT NULL, stuclass varchar(20) NOT NULL, feeamount numeric(15,2) NOT NULL, fcduedate date NOT NULL, partialpayment char(1) NOT NULL, paidamount numeric(15,2) DEFAULT 0, balancedue numeric(15,2), paidstatus char(1) DEFAULT ''U'' NOT NULL, createdby varchar(50) NOT NULL, createdat timestamp DEFAULT now() NOT NULL, activestatus smallint DEFAULT 1 NOT NULL)', v_schema);

  -- payment
  EXECUTE format('CREATE TABLE %I.payment (pay_id bigint NOT NULL PRIMARY KEY, ins_id integer NOT NULL, inscode varchar(10), stu_id integer NOT NULL, yr_id integer NOT NULL, yrlabel varchar(20), transtotalamount numeric(12,2) NOT NULL, transcurrency varchar(20) DEFAULT ''INR'' NOT NULL, paydate timestamp, paystatus char(1) CHECK (paystatus = ANY(ARRAY[''I'',''C'',''F'',''R''])), paymethod varchar(60), payreference varchar(100), paygwresponse numeric(15,0), payitems text, createdby varchar(100), createdat timestamp DEFAULT now() NOT NULL, activestatus smallint DEFAULT 1 NOT NULL, paynumber varchar(30) UNIQUE, payorderid varchar(100), notification_read boolean DEFAULT false, paychequeno varchar(50), paychequedate date, paybankname varchar(100), recon_status char(1) DEFAULT ''P'', reconciled_by varchar(50), reconciled_date timestamp, bank_reference varchar(100), bank_date date)', v_schema);

  -- paymentdetails
  EXECUTE format('CREATE TABLE %I.paymentdetails (pyd_id bigint NOT NULL PRIMARY KEY, pay_id bigint NOT NULL, dem_id integer NOT NULL, yr_id integer NOT NULL, yrlabel varchar(20), ins_id integer NOT NULL, transcurrency varchar(20) DEFAULT ''INR'' NOT NULL, transtotalamount numeric(12,2) NOT NULL, activestatus smallint DEFAULT 1 NOT NULL)', v_schema);

  -- paymentgateway
  EXECUTE format('CREATE TABLE %I.paymentgateway (gw_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY, gwname varchar(100) NOT NULL, gwapikey varchar(255), gwapisecret varchar(255), activestatus smallint DEFAULT 1 NOT NULL)', v_schema);

  -- sequence
  EXECUTE format('CREATE TABLE %I.sequence (seq_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY, ins_id integer NOT NULL, mod_id integer NOT NULL, yr_id integer NOT NULL, yrlabel varchar(9) NOT NULL, actname varchar(30) NOT NULL, seqname varchar(10) NOT NULL, isprefix char(1) NOT NULL, seqprefix varchar(8) NOT NULL, seqstart numeric(9,0) NOT NULL, seqwidth numeric(1,0) NOT NULL, sequid varchar(18) NOT NULL, seqcurno numeric(9,0) NOT NULL, createdon timestamp DEFAULT now() NOT NULL, activestatus smallint DEFAULT 1 NOT NULL, fg_id integer)', v_schema);

  -- shoppingcart
  EXECUTE format('CREATE TABLE %I.shoppingcart (car_id integer NOT NULL PRIMARY KEY, yr_id integer NOT NULL, yrlabel varchar(9), ins_id integer NOT NULL, stu_id bigint NOT NULL, transtype varchar(10) NOT NULL, transdate date DEFAULT CURRENT_DATE NOT NULL, transcurrency varchar(20) DEFAULT ''INR'' NOT NULL, transtotalamount numeric(12,2) NOT NULL, carinitiated char(1) DEFAULT ''N'' NOT NULL, createdby varchar(50) NOT NULL, createdon timestamp DEFAULT now() NOT NULL, activestatus smallint DEFAULT 1 NOT NULL)', v_schema);
  EXECUTE format('CREATE UNIQUE INDEX unique_active_cart_per_student ON %I.shoppingcart (stu_id) WHERE activestatus = 1', v_schema);

  -- shoppingcartdetails
  EXECUTE format('CREATE TABLE %I.shoppingcartdetails (cd_id integer NOT NULL PRIMARY KEY, car_id integer NOT NULL, yr_id integer NOT NULL, yrlabel varchar(9), ins_id integer NOT NULL, dem_id bigint NOT NULL, transdetail_id integer, transcurrency varchar(20) DEFAULT ''INR'' NOT NULL, transtotalamount numeric(12,2) NOT NULL, activestatus smallint DEFAULT 1 NOT NULL)', v_schema);

  -- notice
  EXECUTE format('CREATE TABLE %I.notice (notice_id bigint NOT NULL PRIMARY KEY, ins_id integer NOT NULL, noticetitle text NOT NULL, noticedesc text, noticepriority varchar(20) DEFAULT ''Normal'', noticecategory varchar(50) DEFAULT ''General'', noticetarget text, createdby varchar(50), createdat timestamptz DEFAULT now(), activestatus integer DEFAULT 1, noticefromdate date, noticetodate date)', v_schema);
  EXECUTE format('CREATE INDEX idx_notice_ins_id ON %I.notice (ins_id)', v_schema);

  -- notification
  EXECUTE format('CREATE TABLE %I.notification (noti_id bigint NOT NULL PRIMARY KEY, ins_id integer NOT NULL, stu_id integer, notice_id bigint, notititle text, notibody text, notitype varchar(50), isread integer DEFAULT 0, createdat timestamptz DEFAULT now(), activestatus integer DEFAULT 1)', v_schema);
  EXECUTE format('CREATE INDEX idx_notification_notice_id ON %I.notification(notice_id)', v_schema);
  EXECUTE format('CREATE INDEX idx_notification_ins_id ON %I.notification (ins_id)', v_schema);
  EXECUTE format('CREATE INDEX idx_notification_stu_id ON %I.notification (stu_id)', v_schema);

  -- userlogin
  EXECUTE format('CREATE TABLE %I.userlogin (ul_id bigint NOT NULL PRIMARY KEY, ins_id integer NOT NULL, inscode varchar(10) NOT NULL, yr_id integer NOT NULL, yrlabel varchar(9), uluser varchar(50), ulusetype smallint, ultime timestamp, ulattempt smallint DEFAULT 0, ulip varchar(40), ullocation varchar(50), ulsuccess char(1) DEFAULT ''N'' NOT NULL, ulsesid numeric, ulsesstart timestamp DEFAULT now() NOT NULL, ulsesend timestamp, ulsestime timestamp)', v_schema);

  -- institutionusers (per-schema, not public)
  EXECUTE format('CREATE TABLE %I.institutionusers (use_id integer NOT NULL PRIMARY KEY, ins_id integer, inscode varchar(10) NOT NULL, usename varchar(50) NOT NULL, usemail varchar(254) NOT NULL, usephone varchar(30), usepassword varchar(250), usestadate date DEFAULT CURRENT_DATE NOT NULL, usemaiotp numeric(8,0), usemobotp numeric(6,0), useotpstatus smallint DEFAULT 0 NOT NULL CHECK (useotpstatus = ANY(ARRAY[0,1,2])), usedob date NOT NULL, usecategory varchar(30), ur_id integer NOT NULL, urname varchar(50) NOT NULL, des_id integer NOT NULL, desname varchar(50) NOT NULL, userepto integer NOT NULL, approvedby varchar(50), approveddate timestamp DEFAULT now(), suspendeddate date, suspendedby varchar(50), terminateddate date, terminatedby varchar(50), activestatus smallint DEFAULT 1 NOT NULL CHECK (activestatus = ANY(ARRAY[1,2,9])), terminatedreason text)', v_schema);

  -- student_import
  EXECUTE format('CREATE TABLE %I.student_import (imp_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, ins_id integer NOT NULL, inscode varchar(10) NOT NULL, yr_id integer NOT NULL, yrlabel varchar(9), stuadmno varchar(25) NOT NULL, stuname varchar(50) NOT NULL, stugender char(1), studob date, stuadmdate date, stuclass varchar(20) NOT NULL, courname varchar(20), stumobile varchar(30), stuemail varchar(254), concession varchar(50), stuaddress text, stucity varchar(50), stustate varchar(50), stucountry varchar(50), stupin varchar(6), stubloodgrp varchar(20), fathername varchar(50), fathermobile varchar(30), fatheroccupation varchar(50), mothername varchar(50), mothermobile varchar(30), motheroccupation varchar(50), guardianname varchar(50), guardianmobile varchar(30), guardianoccupation varchar(50), payincharge varchar(50), payinchargemob varchar(30), admname varchar(50), quoname varchar(50), batch varchar(9), admittyear varchar(9), cla_id smallint, cour_id integer, status varchar(10) DEFAULT ''PENDING'', error_msg text, created_at timestamp DEFAULT now())', v_schema);

  -- FOREIGN KEYS
  EXECUTE format('ALTER TABLE %I.paymentdetails ADD CONSTRAINT fk_paymentdetails_payment FOREIGN KEY (pay_id) REFERENCES %I.payment(pay_id)', v_schema, v_schema);
  EXECUTE format('ALTER TABLE %I.shoppingcartdetails ADD CONSTRAINT shoppingcartdetails_car_id_fkey FOREIGN KEY (car_id) REFERENCES %I.shoppingcart(car_id)', v_schema, v_schema);
  EXECUTE format('ALTER TABLE %I.shoppingcartdetails ADD CONSTRAINT shoppingcartdetails_dem_id_fkey FOREIGN KEY (dem_id) REFERENCES %I.feedemand(dem_id)', v_schema, v_schema);

  -- ============================================
  -- TRIGGER FUNCTIONS (per schema)
  -- ============================================

  -- Auto-increment triggers for all tables
  EXECUTE format('CREATE FUNCTION %I.set_yr_id() RETURNS trigger LANGUAGE plpgsql AS $t$ BEGIN IF NEW.yr_id IS NULL OR NEW.yr_id = 0 THEN NEW.yr_id := COALESCE((SELECT MAX(yr_id) FROM %I.year), 0) + 1; END IF; RETURN NEW; END; $t$', v_schema, v_schema);
  EXECUTE format('CREATE TRIGGER trg_year_yr_id BEFORE INSERT ON %I.year FOR EACH ROW EXECUTE FUNCTION %I.set_yr_id()', v_schema, v_schema);

  -- students: sequence-backed id, no hardcoded storage URL (photos resolved client-side)
  EXECUTE format('CREATE SEQUENCE %I.students_stu_id_seq', v_schema);
  EXECUTE format('CREATE FUNCTION %I.set_stu_id() RETURNS trigger LANGUAGE plpgsql AS $t$ BEGIN IF NEW.stu_id IS NULL OR NEW.stu_id = 0 THEN NEW.stu_id := nextval(''%I.students_stu_id_seq''); END IF; IF (NEW.cour_id IS NULL OR NEW.cour_id = 0) AND NEW.courname IS NOT NULL AND TRIM(NEW.courname) != '''' THEN SELECT c.cour_id INTO NEW.cour_id FROM %I.course c WHERE UPPER(TRIM(c.courname)) = UPPER(TRIM(NEW.courname)) AND c.ins_id = NEW.ins_id LIMIT 1; END IF; RETURN NEW; END; $t$', v_schema, v_schema, v_schema);
  EXECUTE format('CREATE TRIGGER trg_students_before_insert BEFORE INSERT ON %I.students FOR EACH ROW EXECUTE FUNCTION %I.set_stu_id()', v_schema, v_schema);

  -- parents: sequence-backed id
  EXECUTE format('CREATE SEQUENCE %I.parents_par_id_seq', v_schema);
  EXECUTE format('CREATE FUNCTION %I.set_par_id() RETURNS trigger LANGUAGE plpgsql AS $t$ BEGIN IF NEW.par_id IS NULL OR NEW.par_id = 0 THEN NEW.par_id := nextval(''%I.parents_par_id_seq''); END IF; RETURN NEW; END; $t$', v_schema, v_schema);
  EXECUTE format('CREATE TRIGGER trg_parents_before_insert BEFORE INSERT ON %I.parents FOR EACH ROW EXECUTE FUNCTION %I.set_par_id()', v_schema, v_schema);

  -- parentdetail: sequence-backed id
  EXECUTE format('CREATE SEQUENCE %I.parentdetail_pd_id_seq', v_schema);
  EXECUTE format('CREATE FUNCTION %I.set_pd_id() RETURNS trigger LANGUAGE plpgsql AS $t$ BEGIN IF NEW.pd_id IS NULL OR NEW.pd_id = 0 THEN NEW.pd_id := nextval(''%I.parentdetail_pd_id_seq''); END IF; RETURN NEW; END; $t$', v_schema, v_schema);
  EXECUTE format('CREATE TRIGGER trg_parentdetail_auto_id BEFORE INSERT ON %I.parentdetail FOR EACH ROW EXECUTE FUNCTION %I.set_pd_id()', v_schema, v_schema);

  -- feedemand uses a real sequence (bulk import path — must be O(1) per row)
  EXECUTE format('CREATE SEQUENCE %I.feedemand_dem_id_seq', v_schema);
  EXECUTE format('CREATE FUNCTION %I.set_dem_id() RETURNS trigger LANGUAGE plpgsql AS $t$ BEGIN IF NEW.dem_id IS NULL OR NEW.dem_id = 0 THEN NEW.dem_id := nextval(''%I.feedemand_dem_id_seq''); END IF; IF NEW.demno IS NULL OR TRIM(NEW.demno) = '''' THEN NEW.demno := ''DE'' || RIGHT(SPLIT_PART(COALESCE(NEW.demfeeyear, ''''), ''-'', 1), 2) || ''/'' || LPAD(NEW.dem_id::TEXT, 5, ''0''); END IF; IF NEW.demseqtype IS NULL OR TRIM(NEW.demseqtype) = '''' THEN NEW.demseqtype := ''DEMAND''; END IF; IF (NEW.fee_id IS NULL OR NEW.fee_id = 0) AND NEW.demfeetype IS NOT NULL THEN SELECT ft.fee_id INTO NEW.fee_id FROM %I.feetype ft WHERE ft.feedesc = NEW.demfeetype AND ft.activestatus = 1 LIMIT 1; END IF; RETURN NEW; END; $t$', v_schema, v_schema, v_schema);
  EXECUTE format('CREATE TRIGGER trg_feedemand_before_insert BEFORE INSERT ON %I.feedemand FOR EACH ROW EXECUTE FUNCTION %I.set_dem_id()', v_schema, v_schema);

  -- tempfeedemand uses a real sequence (bulk import path — must be O(1) per row)
  EXECUTE format('CREATE SEQUENCE %I.tempfeedemand_temp_id_seq', v_schema);
  EXECUTE format('CREATE FUNCTION %I.set_temp_id() RETURNS trigger LANGUAGE plpgsql AS $t$ BEGIN IF NEW.temp_id IS NULL THEN NEW.temp_id := nextval(''%I.tempfeedemand_temp_id_seq''); END IF; RETURN NEW; END; $t$', v_schema, v_schema);
  EXECUTE format('CREATE TRIGGER trg_temp_id BEFORE INSERT ON %I.tempfeedemand FOR EACH ROW EXECUTE FUNCTION %I.set_temp_id()', v_schema, v_schema);

  -- Master-table auto-increment sequences. The NULL/0 guard lets callers
  -- supply an explicit id (needed when importing master data from a legacy
  -- system); a plain INSERT without the column gets nextval().
  EXECUTE format('CREATE SEQUENCE %I.feegroup_fg_id_seq', v_schema);
  EXECUTE format('CREATE FUNCTION %I.set_fg_id() RETURNS trigger LANGUAGE plpgsql AS $t$ BEGIN IF NEW.fg_id IS NULL OR NEW.fg_id = 0 THEN NEW.fg_id := nextval(''%I.feegroup_fg_id_seq''); END IF; RETURN NEW; END; $t$', v_schema, v_schema);
  EXECUTE format('CREATE TRIGGER trg_feegroup_fg_id BEFORE INSERT ON %I.feegroup FOR EACH ROW EXECUTE FUNCTION %I.set_fg_id()', v_schema, v_schema);

  EXECUTE format('CREATE SEQUENCE %I.feetype_fee_id_seq', v_schema);
  EXECUTE format('CREATE FUNCTION %I.set_fee_id() RETURNS trigger LANGUAGE plpgsql AS $t$ BEGIN IF NEW.fee_id IS NULL OR NEW.fee_id = 0 THEN NEW.fee_id := nextval(''%I.feetype_fee_id_seq''); END IF; RETURN NEW; END; $t$', v_schema, v_schema);
  EXECUTE format('CREATE TRIGGER trg_feetype_fee_id BEFORE INSERT ON %I.feetype FOR EACH ROW EXECUTE FUNCTION %I.set_fee_id()', v_schema, v_schema);

  EXECUTE format('CREATE SEQUENCE %I.concessioncategory_con_id_seq', v_schema);
  EXECUTE format('CREATE FUNCTION %I.set_con_id() RETURNS trigger LANGUAGE plpgsql AS $t$ BEGIN IF NEW.con_id IS NULL OR NEW.con_id = 0 THEN NEW.con_id := nextval(''%I.concessioncategory_con_id_seq''); END IF; RETURN NEW; END; $t$', v_schema, v_schema);
  EXECUTE format('CREATE TRIGGER trg_concession_con_id BEFORE INSERT ON %I.concessioncategory FOR EACH ROW EXECUTE FUNCTION %I.set_con_id()', v_schema, v_schema);

  EXECUTE format('CREATE SEQUENCE %I.course_cour_id_seq', v_schema);
  EXECUTE format('CREATE FUNCTION %I.set_cour_id() RETURNS trigger LANGUAGE plpgsql AS $t$ BEGIN IF NEW.cour_id IS NULL OR NEW.cour_id = 0 THEN NEW.cour_id := nextval(''%I.course_cour_id_seq''); END IF; RETURN NEW; END; $t$', v_schema, v_schema);
  EXECUTE format('CREATE TRIGGER trg_course_cour_id BEFORE INSERT ON %I.course FOR EACH ROW EXECUTE FUNCTION %I.set_cour_id()', v_schema, v_schema);

  EXECUTE format('CREATE SEQUENCE %I.class_cla_id_seq', v_schema);
  EXECUTE format('CREATE FUNCTION %I.set_cla_id() RETURNS trigger LANGUAGE plpgsql AS $t$ BEGIN IF NEW.cla_id IS NULL OR NEW.cla_id = 0 THEN NEW.cla_id := nextval(''%I.class_cla_id_seq''); END IF; RETURN NEW; END; $t$', v_schema, v_schema);
  EXECUTE format('CREATE TRIGGER trg_class_cla_id BEFORE INSERT ON %I.class FOR EACH ROW EXECUTE FUNCTION %I.set_cla_id()', v_schema, v_schema);

  EXECUTE format('CREATE SEQUENCE %I.classfeedemand_cf_id_seq', v_schema);
  EXECUTE format('CREATE FUNCTION %I.set_cf_id() RETURNS trigger LANGUAGE plpgsql AS $t$ BEGIN IF NEW.cf_id IS NULL THEN NEW.cf_id := nextval(''%I.classfeedemand_cf_id_seq''); END IF; RETURN NEW; END; $t$', v_schema, v_schema);
  EXECUTE format('CREATE TRIGGER trg_classfeedemand_cf_id BEFORE INSERT ON %I.classfeedemand FOR EACH ROW EXECUTE FUNCTION %I.set_cf_id()', v_schema, v_schema);

  EXECUTE format('CREATE SEQUENCE %I.payment_pay_id_seq', v_schema);
  EXECUTE format('CREATE FUNCTION %I.set_pay_id() RETURNS trigger LANGUAGE plpgsql AS $t$ BEGIN IF NEW.pay_id IS NULL OR NEW.pay_id = 0 THEN NEW.pay_id := nextval(''%I.payment_pay_id_seq''); END IF; RETURN NEW; END; $t$', v_schema, v_schema);
  EXECUTE format('CREATE TRIGGER trg_payment_auto_increment BEFORE INSERT ON %I.payment FOR EACH ROW EXECUTE FUNCTION %I.set_pay_id()', v_schema, v_schema);

  EXECUTE format('CREATE SEQUENCE %I.paymentdetails_pyd_id_seq', v_schema);
  EXECUTE format('CREATE FUNCTION %I.set_pyd_id() RETURNS trigger LANGUAGE plpgsql AS $t$ BEGIN IF NEW.pyd_id IS NULL OR NEW.pyd_id = 0 THEN NEW.pyd_id := nextval(''%I.paymentdetails_pyd_id_seq''); END IF; RETURN NEW; END; $t$', v_schema, v_schema);
  EXECUTE format('CREATE TRIGGER trg_paymentdetails_auto_increment BEFORE INSERT ON %I.paymentdetails FOR EACH ROW EXECUTE FUNCTION %I.set_pyd_id()', v_schema, v_schema);

  EXECUTE format('CREATE FUNCTION %I.set_car_id() RETURNS trigger LANGUAGE plpgsql AS $t$ BEGIN NEW.car_id := COALESCE((SELECT MAX(car_id) FROM %I.shoppingcart), 0) + 1; RETURN NEW; END; $t$', v_schema, v_schema);
  EXECUTE format('CREATE TRIGGER trg_generate_car_id BEFORE INSERT ON %I.shoppingcart FOR EACH ROW EXECUTE FUNCTION %I.set_car_id()', v_schema, v_schema);

  EXECUTE format('CREATE FUNCTION %I.set_cd_id() RETURNS trigger LANGUAGE plpgsql AS $t$ BEGIN NEW.cd_id := COALESCE((SELECT MAX(cd_id) FROM %I.shoppingcartdetails), 0) + 1; RETURN NEW; END; $t$', v_schema, v_schema);
  EXECUTE format('CREATE TRIGGER trg_generate_cd_id BEFORE INSERT ON %I.shoppingcartdetails FOR EACH ROW EXECUTE FUNCTION %I.set_cd_id()', v_schema, v_schema);

  EXECUTE format('CREATE FUNCTION %I.set_notice_id() RETURNS trigger LANGUAGE plpgsql AS $t$ BEGIN IF NEW.notice_id IS NULL OR NEW.notice_id = 0 THEN NEW.notice_id := COALESCE((SELECT MAX(notice_id) FROM %I.notice), 0) + 1; END IF; RETURN NEW; END; $t$', v_schema, v_schema);
  EXECUTE format('CREATE TRIGGER trg_notice_id BEFORE INSERT ON %I.notice FOR EACH ROW EXECUTE FUNCTION %I.set_notice_id()', v_schema, v_schema);

  EXECUTE format('CREATE FUNCTION %I.set_noti_id() RETURNS trigger LANGUAGE plpgsql AS $t$ BEGIN IF NEW.noti_id IS NULL OR NEW.noti_id = 0 THEN NEW.noti_id := COALESCE((SELECT MAX(noti_id) FROM %I.notification), 0) + 1; END IF; RETURN NEW; END; $t$', v_schema, v_schema);
  EXECUTE format('CREATE TRIGGER trg_noti_id BEFORE INSERT ON %I.notification FOR EACH ROW EXECUTE FUNCTION %I.set_noti_id()', v_schema, v_schema);

  -- institutionusers auto-increment trigger
  EXECUTE format('CREATE FUNCTION %I.set_use_id() RETURNS trigger LANGUAGE plpgsql AS $t$ BEGIN IF NEW.use_id IS NULL OR NEW.use_id = 0 THEN NEW.use_id := COALESCE((SELECT MAX(use_id) FROM %I.institutionusers), 0) + 1; END IF; RETURN NEW; END; $t$', v_schema, v_schema);
  EXECUTE format('CREATE TRIGGER trg_institutionusers_use_id BEFORE INSERT ON %I.institutionusers FOR EACH ROW EXECUTE FUNCTION %I.set_use_id()', v_schema, v_schema);

  -- institutionusers password hash trigger
  EXECUTE format('CREATE FUNCTION %I.hash_user_password() RETURNS trigger LANGUAGE plpgsql AS $t$ BEGIN IF NEW.usepassword IS NOT NULL AND NEW.usepassword != '''' AND LEFT(NEW.usepassword, 4) != ''$2a$'' AND LEFT(NEW.usepassword, 4) != ''$2b$'' THEN NEW.usepassword := crypt(NEW.usepassword, gen_salt(''bf'', 10)); END IF; RETURN NEW; END; $t$', v_schema);
  EXECUTE format('CREATE TRIGGER hash_user_password_trigger BEFORE INSERT OR UPDATE OF usepassword ON %I.institutionusers FOR EACH ROW EXECUTE FUNCTION %I.hash_user_password()', v_schema, v_schema);

  -- Password hash triggers
  EXECUTE format('CREATE FUNCTION %I.hash_student_password() RETURNS trigger LANGUAGE plpgsql AS $t$ BEGIN IF NEW.stupassword IS NOT NULL AND NEW.stupassword != '''' AND LEFT(NEW.stupassword, 4) != ''$2a$'' AND LEFT(NEW.stupassword, 4) != ''$2b$'' THEN NEW.stupassword := crypt(NEW.stupassword, gen_salt(''bf'', 10)); END IF; RETURN NEW; END; $t$', v_schema);
  EXECUTE format('CREATE TRIGGER hash_student_password_trigger BEFORE INSERT OR UPDATE OF stupassword ON %I.students FOR EACH ROW EXECUTE FUNCTION %I.hash_student_password()', v_schema, v_schema);

  EXECUTE format('CREATE FUNCTION %I.hash_parent_password() RETURNS trigger LANGUAGE plpgsql AS $t$ BEGIN IF NEW.parpassword IS NOT NULL AND NEW.parpassword != '''' AND LEFT(NEW.parpassword, 4) != ''$2a$'' AND LEFT(NEW.parpassword, 4) != ''$2b$'' THEN NEW.parpassword := crypt(NEW.parpassword, gen_salt(''bf'', 10)); END IF; RETURN NEW; END; $t$', v_schema);
  EXECUTE format('CREATE TRIGGER hash_parent_password_trigger BEFORE INSERT OR UPDATE OF parpassword ON %I.parents FOR EACH ROW EXECUTE FUNCTION %I.hash_parent_password()', v_schema, v_schema);

  -- Approve tempfeedemand trigger
  EXECUTE format('CREATE FUNCTION %I.fn_approve_tempfeedemand() RETURNS trigger LANGUAGE plpgsql AS $t$ BEGIN IF NEW.isapproved = true AND (OLD.isapproved = false OR OLD.isapproved IS NULL) THEN INSERT INTO %I.feedemand (ins_id, inscode, yr_id, stu_id, stuadmno, stuclass, courname, demfeeyear, demfeeterm, demfeetype, feeamount, con_id, conamount, balancedue, reconbalancedue, duedate, activestatus, createdat, createdby, paidstatus, paidamount) VALUES (NEW.ins_id, NEW.inscode, NEW.yr_id, NEW.stu_id, NEW.stuadmno, NEW.stuclass, NEW.courname, NEW.demfeeyear, NEW.demfeeterm, NEW.demfeetype, NEW.feeamount, NEW.con_id, NEW.conamount, NEW.balancedue, NEW.feeamount, NEW.duedate, 1, NEW.createdat, NEW.createdby, ''U'', 0); NEW.activestatus := 9; END IF; RETURN NEW; END; $t$', v_schema, v_schema);
  EXECUTE format('CREATE TRIGGER trg_approve_tempfeedemand BEFORE UPDATE ON %I.tempfeedemand FOR EACH ROW EXECUTE FUNCTION %I.fn_approve_tempfeedemand()', v_schema, v_schema);

  -- RLS
  EXECUTE format('ALTER TABLE %I.notice ENABLE ROW LEVEL SECURITY', v_schema);
  EXECUTE format('ALTER TABLE %I.notification ENABLE ROW LEVEL SECURITY', v_schema);
  EXECUTE format('ALTER TABLE %I.tempfeedemand ENABLE ROW LEVEL SECURITY', v_schema);
  EXECUTE format('CREATE POLICY "Allow all" ON %I.notice USING (true) WITH CHECK (true)', v_schema);
  EXECUTE format('CREATE POLICY "Allow all" ON %I.notification USING (true) WITH CHECK (true)', v_schema);
  EXECUTE format('CREATE POLICY "Allow all" ON %I.tempfeedemand USING (true) WITH CHECK (true)', v_schema);
  EXECUTE format('CREATE POLICY "Allow all" ON %I.student_import TO authenticated USING (true) WITH CHECK (true)', v_schema);
  EXECUTE format('ALTER TABLE %I.institutionusers ENABLE ROW LEVEL SECURITY', v_schema);
  EXECUTE format('CREATE POLICY "Allow all" ON %I.institutionusers TO authenticated USING (true) WITH CHECK (true)', v_schema);

  -- PERMISSIONS
  EXECUTE format('GRANT USAGE ON SCHEMA %I TO anon, authenticated', v_schema);
  EXECUTE format('GRANT ALL ON ALL TABLES IN SCHEMA %I TO anon, authenticated', v_schema);
  EXECUTE format('GRANT ALL ON ALL SEQUENCES IN SCHEMA %I TO anon, authenticated', v_schema);
  EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT ALL ON TABLES TO anon, authenticated', v_schema);
  EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT ALL ON SEQUENCES TO anon, authenticated', v_schema);

  -- Auto-create year records if parameters provided
  IF p_ins_id IS NOT NULL AND p_year_label IS NOT NULL THEN
    -- Insert into public.institutionyear
    INSERT INTO public.institutionyear (ins_id, inscode, yrlabel, iyrstadate, iyrenddate, activestatus)
    VALUES (p_ins_id, COALESCE(v_inscode, ''), p_year_label, COALESCE(p_start_date, CURRENT_DATE), COALESCE(p_end_date, CURRENT_DATE + INTERVAL '1 year'), 1)
    ON CONFLICT DO NOTHING;

    -- Insert into schema year table
    EXECUTE format('INSERT INTO %I.year (ins_id, yrlabel, yrstadate, yrenddate, activestatus) VALUES ($1, $2, $3, $4, 1)', v_schema)
    USING p_ins_id, p_year_label, COALESCE(p_start_date, CURRENT_DATE), COALESCE(p_end_date, CURRENT_DATE + INTERVAL '1 year');
  END IF;

  -- Expose schema to PostgREST (may fail on free tier - handled by app login)
  BEGIN
    PERFORM public.expose_schema(v_schema);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'expose_schema skipped: %', SQLERRM;
  END;

END; $$;

-- Create new academic year schema with year records
CREATE OR REPLACE FUNCTION public.create_next_academic_year(
  p_ins_id integer,
  p_year_label text,        -- e.g. '2027-2028'
  p_start_date date,        -- e.g. '2027-06-01'
  p_end_date date           -- e.g. '2028-05-31'
) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_short_name text;
  v_schema text;
BEGIN
  -- Get institution short name
  SELECT lower(inshortname) INTO v_short_name
  FROM public.institution WHERE ins_id = p_ins_id;
  IF v_short_name IS NULL THEN
    RAISE EXCEPTION 'Institution not found for ins_id %', p_ins_id;
  END IF;

  -- Build schema name: shortname + year without hyphen
  v_schema := v_short_name || replace(p_year_label, '-', '');

  -- Create schema with all tables and triggers
  PERFORM public.create_institution_schema(v_schema);

  -- Insert into public.institutionyear
  INSERT INTO public.institutionyear (ins_id, yrlabel, iyrstadate, iyrenddate, activestatus)
  VALUES (p_ins_id, p_year_label, p_start_date, p_end_date, 1)
  ON CONFLICT DO NOTHING;

  -- Insert year record into the new schema
  EXECUTE format('INSERT INTO %I.year (ins_id, yrlabel, yrstadate, yrenddate, activestatus) VALUES ($1, $2, $3, $4, 1)', v_schema)
  USING p_ins_id, p_year_label, p_start_date, p_end_date;

  -- Expose the new schema to PostgREST
  PERFORM public.expose_schema(v_schema);

  RETURN v_schema;
END; $$;

-- ============================================
-- SCHEMA-AWARE RPC FUNCTIONS
-- ============================================

CREATE OR REPLACE FUNCTION public.get_student_counts_by_class(p_ins_id integer) RETURNS TABLE(stuclass text, student_count bigint)
LANGUAGE plpgsql SECURITY DEFINER AS $$ DECLARE v text; BEGIN v := get_institution_schema(p_ins_id); IF v IS NULL THEN RETURN; END IF;
RETURN QUERY EXECUTE format('SELECT stuclass::text, COUNT(*)::bigint FROM %I.students WHERE ins_id = $1 AND activestatus = 1 GROUP BY stuclass ORDER BY stuclass', v) USING p_ins_id; END; $$;

CREATE OR REPLACE FUNCTION public.get_students_by_class(p_ins_id integer, p_class text) RETURNS SETOF json
LANGUAGE plpgsql SECURITY DEFINER AS $$ DECLARE v text; BEGIN v := get_institution_schema(p_ins_id); IF v IS NULL THEN RETURN; END IF;
RETURN QUERY EXECUTE format('SELECT row_to_json(t) FROM (SELECT * FROM %I.students WHERE ins_id = $1 AND activestatus = 1 AND stuclass = $2 ORDER BY stuname) t', v) USING p_ins_id, p_class; END; $$;

CREATE OR REPLACE FUNCTION public.get_fee_demands(p_ins_id integer) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER AS $$ DECLARE v text; r json; BEGIN v := get_institution_schema(p_ins_id); IF v IS NULL THEN RETURN NULL; END IF;
EXECUTE format('SELECT json_agg(json_build_object(''dem_id'',fd.dem_id,''fee_id'',fd.fee_id,''ins_id'',fd.ins_id,''stu_id'',fd.stu_id,''feeamount'',fd.feeamount,''conamount'',fd.conamount,''paidamount'',fd.paidamount,''fineamount'',fd.fineamount,''duedate'',fd.duedate,''paidstatus'',fd.paidstatus,''stuclass'',fd.stuclass,''courname'',fd.courname,''stuadmno'',fd.stuadmno,''demfeetype'',fd.demfeetype,''demfeeterm'',fd.demfeeterm,''balancedue'',fd.balancedue,''reconbalancedue'',fd.reconbalancedue,''stuname'',s.stuname) ORDER BY fd.courname,fd.stuclass) FROM %I.feedemand fd LEFT JOIN %I.students s ON s.stu_id=fd.stu_id WHERE fd.ins_id=$1 AND fd.activestatus=1', v, v) INTO r USING p_ins_id; RETURN r; END; $$;

-- Totals for the institution dashboard.
-- Pending-approval payments are treated as still owed (matches the reports).
--   total_paid    = fee portion of APPROVED payments only
--   total_fine    = fine portion of APPROVED payments only
--   total_pending = balancedue + fee portion of pending-approval payments
-- Unified fee totals: total_pending uses the EXACT same WHERE/JOIN/CTE as
-- get_pending_payment_report so the Admin dashboard card and the
-- Pending Payment Report G.Tot are guaranteed to match. Other totals
-- (demand/paid/fine) span all active feedemand rows, unfiltered.
CREATE OR REPLACE FUNCTION public.get_fee_totals(p_ins_id integer) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v text; r json;
  v_total_pending numeric := 0;
  v_pending_approval_fee numeric := 0;
  v_pending_approval_fine numeric := 0;
BEGIN
  v := get_institution_schema(p_ins_id);
  IF v IS NULL THEN RETURN json_build_object('total_demand',0,'total_pending',0,'total_paid',0,'total_fine',0); END IF;

  -- Pending approval allocations (for deriving total_paid/total_fine below)
  EXECUTE format('
    SELECT COALESCE(SUM(GREATEST(pd.transtotalamount - COALESCE(fd.fineamount,0), 0)),0),
           COALESCE(SUM(LEAST(pd.transtotalamount, COALESCE(fd.fineamount,0))),0)
    FROM %1$I.paymentdetails pd
    JOIN %1$I.payment p ON p.pay_id = pd.pay_id
    JOIN %1$I.feedemand fd ON fd.dem_id = pd.dem_id
    WHERE p.ins_id=$1 AND p.paystatus=''C'' AND p.recon_status=''P'' AND p.activestatus=1
      AND fd.activestatus=1
  ', v) INTO v_pending_approval_fee, v_pending_approval_fine USING p_ins_id;

  -- total_pending: exact copy of report''s outer query (JOIN students, > 0 filter)
  EXECUTE format($sql$
    WITH pending_alloc AS (
      SELECT pd.dem_id,
             SUM(GREATEST(pd.transtotalamount - COALESCE(fd.fineamount, 0), 0)) AS pending_fee
      FROM %1$I.paymentdetails pd
      JOIN %1$I.payment p ON p.pay_id = pd.pay_id
      LEFT JOIN %1$I.feedemand fd ON fd.dem_id = pd.dem_id
      WHERE p.ins_id = $1 AND p.paystatus = 'C'
        AND p.recon_status = 'P' AND p.activestatus = 1
      GROUP BY pd.dem_id
    )
    SELECT COALESCE(SUM(fd.balancedue + COALESCE(pa.pending_fee, 0)), 0)
    FROM %1$I.feedemand fd
    JOIN %1$I.students s ON s.stu_id = fd.stu_id
    LEFT JOIN pending_alloc pa ON pa.dem_id = fd.dem_id
    WHERE fd.ins_id = $1 AND fd.activestatus = 1
      AND (fd.balancedue + COALESCE(pa.pending_fee, 0)) > 0
  $sql$, v) INTO v_total_pending USING p_ins_id;

  -- Other totals over all active feedemand rows
  EXECUTE format('
    SELECT json_build_object(
      ''total_demand'', COALESCE(SUM(feeamount),0),
      ''total_pending'', $2::numeric,
      ''total_paid'',
        GREATEST(
          COALESCE(SUM(paidamount),0)
            - COALESCE(SUM(fineamount) FILTER (WHERE paidstatus=''P'' OR paidamount > 0),0)
            - $3::numeric, 0
        ),
      ''total_fine'',
        GREATEST(
          COALESCE(SUM(fineamount) FILTER (WHERE paidstatus=''P'' OR paidamount > 0),0)
            - $4::numeric, 0
        )
    )
    FROM %I.feedemand WHERE ins_id=$1 AND activestatus=1
  ', v) INTO r USING p_ins_id, v_total_pending, v_pending_approval_fee, v_pending_approval_fine;
  RETURN r;
END; $$;

-- Class-wise summary — approved-only (matches Fee Collection cards / Consolidated Status report).
-- Pending-approval amounts are removed from total_paid/total_fine and added to total_pending.
CREATE OR REPLACE FUNCTION public.get_fee_demand_summary(p_ins_id integer)
RETURNS TABLE(stuclass text, courname text, student_count bigint, fee_types text[], total_demand numeric, total_concession numeric, total_paid numeric, total_pending numeric, total_fine numeric)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v text;
BEGIN
  v := get_institution_schema(p_ins_id);
  IF v IS NULL THEN RETURN; END IF;
  RETURN QUERY EXECUTE format($f$
    WITH pending_alloc AS (
      SELECT pd.dem_id,
             SUM(GREATEST(pd.transtotalamount - COALESCE(fd.fineamount,0), 0)) AS pending_fee,
             SUM(LEAST(pd.transtotalamount, COALESCE(fd.fineamount,0))) AS pending_fine
      FROM %1$I.paymentdetails pd
      JOIN %1$I.payment p ON p.pay_id = pd.pay_id
      LEFT JOIN %1$I.feedemand fd ON fd.dem_id = pd.dem_id
      WHERE p.ins_id = $1 AND p.paystatus = 'C'
        AND p.recon_status = 'P' AND p.activestatus = 1
      GROUP BY pd.dem_id
    )
    SELECT fd.stuclass::text,
           COALESCE(fd.courname,'Other')::text,
           COUNT(DISTINCT fd.stuadmno)::bigint,
           ARRAY_AGG(DISTINCT fd.demfeetype::text ORDER BY fd.demfeetype::text)
             FILTER(WHERE fd.demfeetype IS NOT NULL AND fd.demfeetype<>''),
           SUM(fd.feeamount),
           SUM(fd.conamount),
           GREATEST(
             COALESCE(SUM(fd.paidamount),0)
               - COALESCE(SUM(fd.fineamount) FILTER (WHERE fd.paidstatus='P' OR fd.paidamount > 0),0)
               - COALESCE(SUM(pa.pending_fee),0),
             0
           ) AS total_paid,
           SUM(fd.balancedue + COALESCE(pa.pending_fee, 0)) AS total_pending,
           GREATEST(
             COALESCE(SUM(fd.fineamount) FILTER (WHERE fd.paidstatus='P' OR fd.paidamount > 0),0)
               - COALESCE(SUM(pa.pending_fine),0),
             0
           ) AS total_fine
    FROM %1$I.feedemand fd
    LEFT JOIN pending_alloc pa ON pa.dem_id = fd.dem_id
    WHERE fd.ins_id=$1 AND fd.activestatus=1
    GROUP BY fd.stuclass, fd.courname
    ORDER BY fd.courname, fd.stuclass
  $f$, v) USING p_ins_id;
END; $$;

CREATE OR REPLACE FUNCTION public.get_fee_demands_by_class(p_ins_id integer, p_class text) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER AS $$ DECLARE v text; r json; BEGIN v := get_institution_schema(p_ins_id); IF v IS NULL THEN RETURN NULL; END IF;
EXECUTE format('SELECT json_agg(t) FROM (SELECT fd.*,s.stuname FROM %I.feedemand fd LEFT JOIN %I.students s ON s.stu_id=fd.stu_id WHERE fd.ins_id=$1 AND fd.activestatus=1 AND fd.stuclass=$2 ORDER BY fd.stuadmno) t', v, v) INTO r USING p_ins_id, p_class; RETURN r; END; $$;

CREATE OR REPLACE FUNCTION public.get_fee_demands_pending(p_ins_id integer) RETURNS SETOF json
LANGUAGE plpgsql SECURITY DEFINER AS $$ DECLARE v text; BEGIN v := get_institution_schema(p_ins_id); IF v IS NULL THEN RETURN; END IF;
RETURN QUERY EXECUTE format('SELECT row_to_json(t) FROM (SELECT td.temp_id,td.stuadmno,s.stuname,s.stuclass,td.courname,td.demfeeyear,td.demfeeterm,td.demfeetype,td.feeamount,td.con_id,td.conamount,td.balancedue,td.createdby,td.isapproved,td.ins_id,COALESCE(c.condesc,''-'') as stucondesc FROM %I.tempfeedemand td LEFT JOIN %I.students s ON s.stuadmno=td.stuadmno AND s.ins_id=td.ins_id LEFT JOIN %I.concessioncategory c ON c.con_id=td.con_id WHERE td.ins_id=$1 AND td.activestatus=1) t', v, v, v) USING p_ins_id; END; $$;

CREATE OR REPLACE FUNCTION public.get_fee_summary(p_ins_id integer) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER AS $$ DECLARE v text; r json; BEGIN v := get_institution_schema(p_ins_id);
IF v IS NULL THEN RETURN json_build_object('total_pending',0,'pending_count',0); END IF;
EXECUTE format('SELECT json_build_object(''total_pending'',COALESCE(SUM(balancedue),0),''pending_count'',COUNT(*)) FROM %I.feedemand WHERE ins_id=$1 AND paidstatus=''U''', v) INTO r USING p_ins_id; RETURN r; END; $$;

CREATE OR REPLACE FUNCTION public.get_payments_by_date_range(p_ins_id integer, p_from_date date, p_to_date date) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER AS $$ DECLARE v text; r json; BEGIN v := get_institution_schema(p_ins_id); IF v IS NULL THEN RETURN NULL; END IF;
EXECUTE format('SELECT json_agg(t ORDER BY t.paydate DESC) FROM (SELECT p.pay_id,p.ins_id,p.stu_id,p.transtotalamount,p.paydate,p.paystatus,p.paymethod,p.paynumber,p.payreference,p.recon_status,p.createdat,s.stuname,s.stuadmno,s.stuclass,s.courname FROM %I.payment p LEFT JOIN %I.students s ON s.stu_id=p.stu_id WHERE p.ins_id=$1 AND p.paystatus=''C'' AND p.activestatus=1 AND p.paydate::date>=$2 AND p.paydate::date<=$3) t', v, v) INTO r USING p_ins_id, p_from_date, p_to_date; RETURN r; END; $$;

CREATE OR REPLACE FUNCTION public.fn_get_transactions(p_ins_id integer) RETURNS TABLE(pay_id integer, ins_id integer, stu_id integer, payno text, stuname text, payamount numeric, paycurrency text, paymethod text, payreference text, paydate timestamptz, paystatus text, createdat timestamptz, recon_status text)
LANGUAGE plpgsql SECURITY DEFINER AS $$ DECLARE v text; BEGIN v := get_institution_schema(p_ins_id); IF v IS NULL THEN RETURN; END IF;
RETURN QUERY EXECUTE format('SELECT p.pay_id::int,p.ins_id::int,p.stu_id::int,p.paynumber::text,s.stuname::text,p.transtotalamount,p.transcurrency::text,p.paymethod::text,p.payreference::text,p.paydate::timestamptz,p.paystatus::text,p.createdat::timestamptz,p.recon_status::text FROM %I.payment p LEFT JOIN %I.students s ON s.stu_id=p.stu_id WHERE p.ins_id=$1 ORDER BY p.createdat DESC', v, v) USING p_ins_id; END; $$;

-- Super Admin Dashboard: all institutions with finance summary in one call
CREATE OR REPLACE FUNCTION public.get_super_admin_dashboard() RETURNS json
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  rec RECORD;
  v_schema text;
  v_demand numeric;
  v_collected numeric;
  v_pending numeric;
  v_transactions int;
  v_students int;
  results json;
BEGIN
  CREATE TEMP TABLE IF NOT EXISTS _sa_dashboard (
    ins_id int, insname text, inscode text, inshortname text, inslogo text,
    activestatus int, total_demand numeric, total_collected numeric,
    total_pending numeric, transaction_count int, student_count int
  ) ON COMMIT DROP;

  TRUNCATE _sa_dashboard;

  FOR rec IN
    SELECT i.ins_id, i.insname, i.inscode, i.inshortname, i.inslogo, i.activestatus
    FROM institution i WHERE i.activestatus = 1 ORDER BY i.ins_id
  LOOP
    v_demand := 0; v_collected := 0; v_pending := 0; v_transactions := 0; v_students := 0;

    -- Get schema for this institution
    SELECT lower(rec.inshortname) || replace(iy.yrlabel, '-', '')
    INTO v_schema
    FROM institutionyear iy
    WHERE iy.ins_id = rec.ins_id AND iy.activestatus = 1
    ORDER BY iy.iyr_id DESC LIMIT 1;

    IF v_schema IS NOT NULL AND EXISTS (
      SELECT 1 FROM information_schema.tables WHERE table_schema = v_schema AND table_name = 'feedemand'
    ) THEN
      -- Fee totals (fines are now stored as separate FINE demand rows, so totals tally naturally)
      -- Total Collection = fee-only, approved only (exclude fine portion AND pending-approval payments)
      EXECUTE format('SELECT COALESCE(SUM(feeamount),0), COALESCE(SUM(paidamount),0) - COALESCE(SUM(fineamount) FILTER (WHERE paidstatus=''P'' OR paidamount > 0),0), COALESCE(SUM(balancedue),0) FROM %I.feedemand WHERE ins_id=$1 AND activestatus=1', v_schema)
      INTO v_demand, v_collected, v_pending USING rec.ins_id;
      -- Pending-approval fee portion: subtract from collected AND add to pending,
      -- so Super Admin matches the Pending Payment Report.
      DECLARE v_pending_approval_fee numeric := 0; BEGIN
        EXECUTE format('
          SELECT COALESCE(SUM(GREATEST(pd.transtotalamount - COALESCE(fd.fineamount,0), 0)),0)
          FROM %1$I.paymentdetails pd
          JOIN %1$I.payment p ON p.pay_id = pd.pay_id
          LEFT JOIN %1$I.feedemand fd ON fd.dem_id = pd.dem_id
          WHERE p.ins_id=$1 AND p.paystatus=''C'' AND p.recon_status=''P'' AND p.activestatus=1
        ', v_schema) INTO v_pending_approval_fee USING rec.ins_id;
        v_collected := GREATEST(v_collected - v_pending_approval_fee, 0);
        v_pending := v_pending + v_pending_approval_fee;
      END;

      -- Transaction count
      EXECUTE format('SELECT COUNT(*) FROM %I.payment WHERE ins_id=$1 AND paystatus=''C'' AND activestatus=1', v_schema)
      INTO v_transactions USING rec.ins_id;

      -- Student count
      EXECUTE format('SELECT COUNT(*) FROM %I.students WHERE ins_id=$1 AND activestatus=1', v_schema)
      INTO v_students USING rec.ins_id;
    END IF;

    INSERT INTO _sa_dashboard VALUES (
      rec.ins_id, rec.insname, rec.inscode, rec.inshortname, rec.inslogo,
      rec.activestatus, v_demand, v_collected, v_pending, v_transactions, v_students
    );
  END LOOP;

  SELECT json_agg(row_to_json(t)) INTO results FROM _sa_dashboard t;
  RETURN COALESCE(results, '[]'::json);
END; $$;

-- Super Admin Institution Detail: course-wise collection and pending
CREATE OR REPLACE FUNCTION public.get_institution_course_summary(p_ins_id integer) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_schema text;
  results json;
BEGIN
  SELECT lower(i.inshortname) || replace(iy.yrlabel, '-', '')
  INTO v_schema
  FROM institution i
  JOIN institutionyear iy ON iy.ins_id = i.ins_id AND iy.activestatus = 1
  WHERE i.ins_id = p_ins_id
  ORDER BY iy.iyr_id DESC LIMIT 1;

  IF v_schema IS NULL OR NOT EXISTS (
    SELECT 1 FROM information_schema.tables WHERE table_schema = v_schema AND table_name = 'feedemand'
  ) THEN
    RETURN '[]'::json;
  END IF;

  EXECUTE format('
    SELECT json_agg(row_to_json(t) ORDER BY t.course)
    FROM (
      SELECT
        COALESCE(s.courname, ''Other'') as course,
        COALESCE(fd.stuclass, ''Unknown'') as class,
        COALESCE(SUM(fd.paidamount), 0) as collection,
        COALESCE(SUM(fd.balancedue), 0) as pending,
        COUNT(DISTINCT fd.stu_id) as students
      FROM %I.feedemand fd
      LEFT JOIN %I.students s ON s.stu_id = fd.stu_id AND s.ins_id = fd.ins_id
      WHERE fd.ins_id = $1 AND fd.activestatus = 1
      GROUP BY COALESCE(s.courname, ''Other''), COALESCE(fd.stuclass, ''Unknown'')
      ORDER BY course, class
    ) t
  ', v_schema, v_schema) INTO results USING p_ins_id;

  RETURN COALESCE(results, '[]'::json);
END; $$;

-- Reports: all feedemand with student names (single call, no row limit)
CREATE OR REPLACE FUNCTION public.get_fee_report_data(p_ins_id integer) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v text; r json;
BEGIN
  v := get_institution_schema(p_ins_id);
  IF v IS NULL THEN RETURN '[]'::json; END IF;
  EXECUTE format('SELECT json_agg(t) FROM (SELECT fd.fee_id,fd.stu_id,fd.feeamount,fd.conamount,fd.paidamount,fd.balancedue,fd.reconbalancedue,fd.paidstatus,fd.stuclass,fd.courname,fd.stuadmno,fd.demfeetype,fd.demfeeterm,fd.activestatus,s.stuname FROM %I.feedemand fd LEFT JOIN %I.students s ON s.stu_id=fd.stu_id AND s.ins_id=fd.ins_id WHERE fd.ins_id=$1 AND fd.activestatus=1 ORDER BY fd.stuadmno) t', v, v) INTO r USING p_ins_id;
  RETURN COALESCE(r, '[]'::json);
END; $$;

-- Student Ledger: demands + payments for a student
CREATE OR REPLACE FUNCTION public.get_student_ledger_data(p_ins_id integer, p_stuadmno text) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v text; r json;
BEGIN
  v := get_institution_schema(p_ins_id);
  IF v IS NULL THEN RETURN '{}'::json; END IF;
  EXECUTE format('SELECT json_build_object(
    ''demands'', COALESCE((SELECT json_agg(d) FROM (SELECT dem_id,demfeeterm,demfeetype,feeamount,conamount,paidamount,balancedue,paidstatus,duedate,pay_id FROM %I.feedemand WHERE ins_id=$1 AND stuadmno=$2 AND activestatus=1 ORDER BY duedate) d), ''[]''::json),
    ''payments'', COALESCE((SELECT json_agg(p) FROM (SELECT p.pay_id,p.transtotalamount,p.paydate,p.paystatus,p.paymethod,p.paynumber,p.recon_status FROM %I.payment p WHERE p.ins_id=$1 AND p.stu_id=(SELECT stu_id FROM %I.students WHERE stuadmno=$2 AND ins_id=$1 LIMIT 1) AND p.activestatus=1 ORDER BY p.paydate DESC) p), ''[]''::json)
  )', v, v, v) INTO r USING p_ins_id, p_stuadmno;
  RETURN COALESCE(r, '{}'::json);
END; $$;

-- Bank Reconciliation: pending + reconciled payments in one call
CREATE OR REPLACE FUNCTION public.get_bank_recon_data(p_ins_id integer) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v text; r json;
BEGIN
  v := get_institution_schema(p_ins_id);
  IF v IS NULL THEN RETURN '{}'::json; END IF;
  EXECUTE format('SELECT json_build_object(
    ''pending'', COALESCE((SELECT json_agg(t) FROM (SELECT p.pay_id,p.paynumber,p.transtotalamount,p.paydate,p.paymethod,p.payreference,p.paychequeno,p.payorderid,p.stu_id,p.createdby,p.recon_status,s.stuname,s.stuadmno FROM %I.payment p LEFT JOIN %I.students s ON s.stu_id=p.stu_id AND s.ins_id=p.ins_id WHERE p.ins_id=$1 AND p.paystatus=''C'' AND p.recon_status=''P'' AND p.activestatus=1 ORDER BY p.paydate DESC) t), ''[]''::json),
    ''reconciled'', COALESCE((SELECT json_agg(t) FROM (SELECT p.pay_id,p.paynumber,p.transtotalamount,p.paydate,p.paymethod,p.payreference,p.stu_id,p.createdby,p.recon_status,p.reconciled_by,p.reconciled_date,p.bank_reference,s.stuname,s.stuadmno FROM %I.payment p LEFT JOIN %I.students s ON s.stu_id=p.stu_id AND s.ins_id=p.ins_id WHERE p.ins_id=$1 AND p.paystatus=''C'' AND p.recon_status=''R'' AND p.activestatus=1 ORDER BY p.reconciled_date DESC LIMIT 100) t), ''[]''::json)
  )', v, v, v, v) INTO r USING p_ins_id;
  RETURN COALESCE(r, '{}'::json);
END; $$;

-- Pending Fee Export: feedemand with student names for export
CREATE OR REPLACE FUNCTION public.get_pending_export_data(p_ins_id integer) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v text; r json;
BEGIN
  v := get_institution_schema(p_ins_id);
  IF v IS NULL THEN RETURN '[]'::json; END IF;
  EXECUTE format('SELECT json_agg(t) FROM (SELECT fd.stu_id,fd.stuadmno,fd.stuclass,fd.courname,fd.demfeetype,fd.demfeeterm,fd.feeamount,fd.conamount,fd.balancedue,fd.reconbalancedue,fd.paidstatus,s.stuname FROM %I.feedemand fd LEFT JOIN %I.students s ON s.stu_id=fd.stu_id AND s.ins_id=fd.ins_id WHERE fd.ins_id=$1 AND fd.activestatus=1 ORDER BY fd.courname,fd.stuclass,fd.stuadmno) t', v, v) INTO r USING p_ins_id;
  RETURN COALESCE(r, '[]'::json);
END; $$;

-- Master import (public + schema for classfeedemand)
CREATE OR REPLACE FUNCTION public.process_master_import(p_ins_id integer) RETURNS TABLE(total integer, imported integer, skipped integer)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE rec RECORD; v_total int:=0; v_imported int:=0; v_skipped int:=0; v_fg_id int; v_schema text; v_id int; v_adm_id smallint;
BEGIN
  v_schema := get_institution_schema(p_ins_id);
  FOR rec IN SELECT * FROM master_import WHERE ins_id=p_ins_id AND status='PENDING' ORDER BY imp_id LOOP
    v_total := v_total+1;
    BEGIN
      -- Every import row must carry an explicit id in col1. Blank or
      -- non-numeric ids are rejected outright — no sequence fallback.
      IF rec.col1 IS NULL OR TRIM(rec.col1) = '' THEN
        UPDATE master_import SET status='ERROR', error_msg='Missing id in column 1' WHERE imp_id=rec.imp_id;
        v_skipped := v_skipped+1; CONTINUE;
      END IF;
      BEGIN v_id := TRIM(rec.col1)::int; EXCEPTION WHEN OTHERS THEN
        UPDATE master_import SET status='ERROR', error_msg='Invalid id: "'||rec.col1||'"' WHERE imp_id=rec.imp_id;
        v_skipped := v_skipped+1; CONTINUE;
      END;
      IF v_schema IS NULL THEN
        UPDATE master_import SET status='ERROR', error_msg='No institution schema' WHERE imp_id=rec.imp_id;
        v_skipped := v_skipped+1; CONTINUE;
      END IF;

      CASE rec.imp_type
      WHEN 'FEEGROUP' THEN
        EXECUTE format('INSERT INTO %I.feegroup(fg_id,fgdesc,ins_id,yr_id,yrlabel,ban_id,activestatus) VALUES($1,$2,$3,0,COALESCE($4,''''),NULLIF($5,'''')::int,1)', v_schema) USING v_id,TRIM(rec.col2),p_ins_id,TRIM(rec.col3),TRIM(rec.col4);
      WHEN 'FEETYPE' THEN
        EXECUTE format('SELECT fg_id FROM %I.feegroup WHERE UPPER(TRIM(fgdesc))=UPPER($1) AND ins_id=$2 AND activestatus=1 LIMIT 1', v_schema) INTO v_fg_id USING TRIM(rec.col4),p_ins_id;
        IF v_fg_id IS NULL THEN UPDATE master_import SET status='ERROR',error_msg='Fee group "'||rec.col4||'" not found' WHERE imp_id=rec.imp_id; v_skipped:=v_skipped+1; CONTINUE; END IF;
        EXECUTE format('INSERT INTO %I.feetype(fee_id,feedesc,feeshort,fg_id,yr_id,yrlabel,feefineapplicable,activestatus,ins_id) VALUES($1,$2,$3,$4,0,COALESCE($5,''''),COALESCE(NULLIF($6,'''')::smallint,0),1,$7)', v_schema) USING v_id,TRIM(rec.col2),TRIM(rec.col3),v_fg_id,TRIM(rec.col5),TRIM(rec.col6),p_ins_id;
      WHEN 'CONCESSION' THEN
        EXECUTE format('INSERT INTO %I.concessioncategory(con_id,condesc,ins_id,ordid,activestatus) VALUES($1,$2,$3,NULLIF($4,'''')::int,1)', v_schema) USING v_id,TRIM(rec.col2),p_ins_id,TRIM(rec.col3);
      WHEN 'CLASSFEEDEMAND' THEN
        -- cf_id is assigned by the set_cf_id BEFORE-INSERT trigger; col1 is a
        -- placeholder row number that we ignore here.
        -- col7 is an admissiontype NAME (e.g. "MANAGEMENT QUOTA"). Look up
        -- adm_id from the per-schema admissiontype master and store that
        -- smallint id. Falls back to direct numeric cast for legacy 1/2/3.
        IF NULLIF(TRIM(rec.col7),'') IS NULL THEN
          v_adm_id := NULL;
        ELSIF TRIM(rec.col7) ~ '^\d+$' THEN
          v_adm_id := TRIM(rec.col7)::smallint;
        ELSE
          EXECUTE format('SELECT adm_id FROM %I.admissiontype WHERE UPPER(TRIM(admname))=UPPER($1) AND ins_id=$2 AND activestatus=1 LIMIT 1', v_schema)
            INTO v_adm_id USING TRIM(rec.col7), p_ins_id;
          IF v_adm_id IS NULL THEN
            UPDATE master_import SET status='ERROR', error_msg='Admission Type "'||rec.col7||'" not found in admissiontype master' WHERE imp_id=rec.imp_id;
            v_skipped := v_skipped+1;
            CONTINUE;
          END IF;
        END IF;
        EXECUTE format('INSERT INTO %I.classfeedemand(cfclass,cfterm,cffeetype,cfamount,cfdduedate,admissiontype) VALUES($1,NULLIF($2,''''),$3,NULLIF($4,'''')::numeric(12,2),NULLIF($5,'''')::date,$6)', v_schema)
          USING TRIM(rec.col2),TRIM(rec.col3),TRIM(rec.col4),TRIM(rec.col5),TRIM(rec.col6),v_adm_id;
      ELSE
        UPDATE master_import SET status='ERROR',error_msg='Unknown type: '||rec.imp_type WHERE imp_id=rec.imp_id; v_skipped:=v_skipped+1; CONTINUE;
      END CASE;
      UPDATE master_import SET status='DONE' WHERE imp_id=rec.imp_id; v_imported:=v_imported+1;
    EXCEPTION WHEN unique_violation THEN
      UPDATE master_import SET status='ERROR', error_msg='ID '||COALESCE(v_id::text, rec.col1)||' already exists — row rejected' WHERE imp_id=rec.imp_id; v_skipped:=v_skipped+1;
    WHEN OTHERS THEN
      UPDATE master_import SET status='ERROR',error_msg=SQLERRM WHERE imp_id=rec.imp_id; v_skipped:=v_skipped+1;
    END;
  END LOOP;
  RETURN QUERY SELECT v_total, v_imported, v_skipped;
END; $$;

-- Student import (schema-aware)
CREATE OR REPLACE FUNCTION public.process_student_import(p_ins_id integer) RETURNS TABLE(total integer, imported integer, skipped integer)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE rec RECORD; v_stu_id bigint; v_par_id bigint; v_con_id integer; v_total int:=0; v_imported int:=0; v_skipped int:=0; v_schema text;
BEGIN
  v_schema := get_institution_schema(p_ins_id);
  IF v_schema IS NULL THEN RAISE EXCEPTION 'No schema for ins_id %', p_ins_id; END IF;
  FOR rec IN EXECUTE format('SELECT * FROM %I.student_import WHERE ins_id=$1 AND status=''PENDING'' ORDER BY imp_id', v_schema) USING p_ins_id LOOP
    v_total:=v_total+1;
    BEGIN
      IF (rec.payinchargemob IS NULL OR TRIM(rec.payinchargemob)='') OR (rec.payincharge IS NULL OR TRIM(rec.payincharge)='') THEN
        EXECUTE format('UPDATE %I.student_import SET status=''NO_PARENT'',error_msg=''Missing payincharge'' WHERE imp_id=$1', v_schema) USING rec.imp_id; v_skipped:=v_skipped+1; CONTINUE;
      END IF;
      v_con_id:=NULL;
      IF rec.concession IS NOT NULL AND TRIM(rec.concession)!='' THEN EXECUTE format('SELECT con_id FROM %I.concessioncategory WHERE UPPER(TRIM(condesc))=UPPER($1) AND ins_id=$2 LIMIT 1', v_schema) INTO v_con_id USING TRIM(rec.concession),p_ins_id; END IF;
      EXECUTE format('INSERT INTO %I.students(ins_id,inscode,yr_id,yrlabel,stuadmno,stuadmdate,stuname,stugender,studob,stumobile,stuemail,stuaddress,stucity,stustate,stucountry,stupin,stubloodgrp,stuclass,courname,cour_id,con_id,stucondesc,stuser_id,stuotpstatus,approvedby,approveddate,suspendedby,terminatedby,activestatus,createdon,admname,quoname,batch,admittyear) VALUES($1,$2,$3,$4,$5,COALESCE($6,CURRENT_DATE),$7,$8,$9,$10,NULLIF($11,''''),$12,$13,$14,$15,$16,$17,$18,$21,$26,$19,NULLIF(TRIM($20),''''),$5,0,'''',now(),'''','''',1,now(),$22,$23,$24,$25) RETURNING stu_id', v_schema) INTO v_stu_id USING rec.ins_id,rec.inscode,rec.yr_id,rec.yrlabel,rec.stuadmno,rec.stuadmdate,rec.stuname,rec.stugender,rec.studob,rec.stumobile,rec.stuemail,rec.stuaddress,rec.stucity,rec.stustate,rec.stucountry,rec.stupin,rec.stubloodgrp,rec.stuclass,v_con_id,rec.concession,rec.courname,rec.admname,rec.quoname,rec.batch,rec.admittyear,rec.cour_id;
      v_par_id:=NULL;
      EXECUTE format('SELECT par_id FROM %I.parents WHERE payinchargemob=$1 LIMIT 1', v_schema) INTO v_par_id USING rec.payinchargemob;
      IF v_par_id IS NULL THEN
        EXECUTE format('INSERT INTO %I.parents(ins_id,yr_id,yrlabel,partype,fathername,fathermobile,fatheroccupation,mothername,mothermobile,motheroccupation,guardianname,guardianmobile,guardianoccupation,payincharge,payinchargemob,parotpstatus,approveddate,activestatus) VALUES($14,$1,$2,''P'',$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,0,now(),1) RETURNING par_id', v_schema) INTO v_par_id USING rec.yr_id,rec.yrlabel,rec.fathername,rec.fathermobile,rec.fatheroccupation,rec.mothername,rec.mothermobile,rec.motheroccupation,rec.guardianname,rec.guardianmobile,rec.guardianoccupation,rec.payincharge,rec.payinchargemob,rec.ins_id;
      END IF;
      EXECUTE format('INSERT INTO %I.parentdetail(yr_id,yrlabel,par_id,stu_id,ins_id,inscode,stuadmno,stuname,stuclass,activestatus) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,1)', v_schema) USING rec.yr_id,rec.yrlabel,v_par_id,v_stu_id,rec.ins_id,rec.inscode,rec.stuadmno,rec.stuname,rec.stuclass;
      EXECUTE format('UPDATE %I.student_import SET status=''DONE'' WHERE imp_id=$1', v_schema) USING rec.imp_id; v_imported:=v_imported+1;
    EXCEPTION WHEN OTHERS THEN
      EXECUTE format('UPDATE %I.student_import SET status=''ERROR'',error_msg=$1 WHERE imp_id=$2', v_schema) USING SQLERRM,rec.imp_id; v_skipped:=v_skipped+1;
    END;
  END LOOP;
  RETURN QUERY SELECT v_total, v_imported, v_skipped;
END; $$;

-- ============================================
-- PAYMENT FUNCTIONS (concurrency-safe with row-level locking)
-- ============================================

-- 1. Initiate payment (creates I status record for Razorpay flow)
CREATE OR REPLACE FUNCTION public.initiate_payment_atomic(p_car_id integer, p_ins_id integer, p_inscode varchar, p_stu_id bigint, p_yr_id integer, p_yrlabel varchar, p_total_amount numeric, p_created_by varchar, p_items jsonb) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_pay_id INTEGER; v_item JSONB; v_dem_id BIGINT; v_balance NUMERIC; v_paid_status CHAR(1); v text;
BEGIN
  v := get_institution_schema(p_ins_id); IF v IS NULL THEN RAISE EXCEPTION 'No schema'; END IF;
  -- Validate and lock each fee demand
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_dem_id:=(v_item->>'dem_id')::BIGINT;
    EXECUTE format('SELECT balancedue,paidstatus FROM %I.feedemand WHERE dem_id=$1 AND activestatus=1',v) INTO v_balance,v_paid_status USING v_dem_id;
    IF v_balance IS NULL THEN RAISE EXCEPTION 'Fee demand % not found',v_dem_id; END IF;
    IF v_paid_status='P' OR v_balance<=0 THEN RAISE EXCEPTION 'Fee demand % already paid',v_dem_id; END IF;
  END LOOP;
  -- Create payment with I status
  EXECUTE format('INSERT INTO %I.payment(ins_id,inscode,stu_id,yr_id,yrlabel,transtotalamount,transcurrency,paydate,paystatus,createdby,recon_status) VALUES($1,$2,$3,$4,$5,$6,''INR'',NOW(),''I'',$7,''P'') RETURNING pay_id',v) INTO v_pay_id USING p_ins_id,p_inscode,p_stu_id,p_yr_id,p_yrlabel,p_total_amount,p_created_by;
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    EXECUTE format('INSERT INTO %I.paymentdetails(pay_id,dem_id,yr_id,yrlabel,ins_id,transcurrency,transtotalamount) VALUES($1,$2,$3,$4,$5,''INR'',$6)',v) USING v_pay_id,(v_item->>'dem_id')::BIGINT,(v_item->>'yr_id')::INTEGER,v_item->>'yrlabel',(v_item->>'ins_id')::INTEGER,(v_item->>'amount')::NUMERIC;
  END LOOP;
  RETURN v_pay_id;
END; $$;

-- 2. Complete payment atomic (single receipt, used for Razorpay)
CREATE OR REPLACE FUNCTION public.complete_payment_atomic(p_pay_id bigint, p_pay_method text, p_pay_reference text, p_items jsonb, p_ins_id integer) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_pay_number TEXT; v_item JSONB; v_dem_id BIGINT; v_amount NUMERIC; v_current_paid NUMERIC; v_current_balance NUMERIC; v_new_paid NUMERIC; v_new_balance NUMERIC; v_stu_id BIGINT; v_pay_status CHAR(1); v text; v_seq RECORD; v_new_no INTEGER;
BEGIN
  v := get_institution_schema(p_ins_id); IF v IS NULL THEN RAISE EXCEPTION 'No schema'; END IF;
  EXECUTE format('SELECT paystatus,stu_id FROM %I.payment WHERE pay_id=$1 FOR UPDATE',v) INTO v_pay_status,v_stu_id USING p_pay_id;
  IF v_pay_status IS NULL THEN RAISE EXCEPTION 'Payment % not found',p_pay_id; END IF;
  IF v_pay_status!='I' THEN RAISE EXCEPTION 'Payment % not Initiated',p_pay_id; END IF;
  -- Generate pay number from first available sequence
  EXECUTE format('SELECT seq_id,sequid,seqwidth,seqcurno FROM %I.sequence WHERE ins_id=$1 LIMIT 1 FOR UPDATE',v) INTO v_seq USING p_ins_id;
  IF v_seq IS NULL THEN v_pay_number:='PAY'||p_pay_id;
  ELSE v_new_no:=v_seq.seqcurno+1; v_pay_number:=regexp_replace(v_seq.sequid,'\d+$','')||lpad(v_new_no::TEXT,v_seq.seqwidth::INTEGER,'0'); EXECUTE format('UPDATE %I.sequence SET seqcurno=$1 WHERE seq_id=$2',v) USING v_new_no,v_seq.seq_id;
  END IF;
  EXECUTE format('UPDATE %I.payment SET paystatus=''C'',paymethod=$1,payreference=$2,paynumber=$3,paydate=NOW(),recon_status=''P'' WHERE pay_id=$4',v) USING p_pay_method,p_pay_reference,v_pay_number,p_pay_id;
  -- Update fee demands atomically
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_dem_id:=(v_item->>'dem_id')::BIGINT; v_amount:=(v_item->>'amount')::NUMERIC;
    EXECUTE format('UPDATE %I.feedemand
                      SET paidamount = COALESCE(paidamount, 0) + $1,
                          balancedue = GREATEST(COALESCE(balancedue, 0) - $1, 0),
                          paidstatus = CASE WHEN GREATEST(COALESCE(balancedue, 0) - $1, 0) <= 0 THEN ''P'' ELSE ''U'' END,
                          pay_id     = $2
                      WHERE dem_id = $3 AND activestatus = 1', v)
    USING v_amount, p_pay_id, v_dem_id;
  END LOOP;
  RETURN v_pay_number;
END; $$;

-- 3. Process grouped payment (per fee group receipts, used for Cash/QR/Cheque)
CREATE OR REPLACE FUNCTION public.process_grouped_payment(
  p_ins_id integer, p_inscode varchar, p_stu_id bigint,
  p_yr_id integer, p_yrlabel varchar, p_total_amount numeric,
  p_created_by varchar, p_pay_method text, p_pay_reference text,
  p_items jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v text; v_fg_id INTEGER; v_pay_id BIGINT; v_pay_number TEXT;
  v_seq RECORD; v_new_no INTEGER;
  v_current_paid NUMERIC; v_current_balance NUMERIC;
  v_new_paid NUMERIC; v_new_balance NUMERIC;
  v_result JSONB := '[]'::jsonb;
  v_group_total NUMERIC;
  itm RECORD; v_fg_ids INTEGER[];
BEGIN
  v := get_institution_schema(p_ins_id);
  IF v IS NULL THEN RAISE EXCEPTION 'No schema found'; END IF;
  v_fg_ids := ARRAY[]::INTEGER[];
  FOR itm IN SELECT x.dem_id, x.yr_id, x.yrlabel, x.amount, x.demfeetype
    FROM jsonb_to_recordset(p_items) AS x(dem_id bigint, yr_id integer, yrlabel text, ins_id integer, amount numeric, demfeetype text)
  LOOP
    v_fg_id := NULL;
    IF itm.demfeetype = 'FINE' THEN
      -- New format: demno starts with 'FNG<fg_id>' (group-wise fine).
      -- Older format: 'FN<orig_dem_id>' (per-demand fine) — fall back to that.
      EXECUTE format($q$
        SELECT CASE
          WHEN fn.demno LIKE 'FNG%%' THEN
            (CASE
              WHEN position('-' in substring(fn.demno from 4)) > 0
                THEN substring(fn.demno from 4 for position('-' in substring(fn.demno from 4)) - 1)::int
              ELSE substring(fn.demno from 4)::int
            END)
          WHEN fn.demno LIKE 'FN%%' THEN
            (SELECT ft.fg_id FROM %I.feedemand orig
             JOIN %I.feetype ft
               ON (orig.fee_id IS NOT NULL AND ft.fee_id = orig.fee_id)
               OR (orig.fee_id IS NULL AND ft.feedesc = orig.demfeetype)
             WHERE orig.dem_id = (
               CASE
                 WHEN position('-' in substring(fn.demno from 3)) > 0
                   THEN substring(fn.demno from 3 for position('-' in substring(fn.demno from 3)) - 1)::bigint
                 ELSE substring(fn.demno from 3)::bigint
               END
             ) AND ft.activestatus = 1 LIMIT 1)
          ELSE NULL
        END
        FROM %I.feedemand fn
        WHERE fn.dem_id = $1
      $q$, v, v, v) INTO v_fg_id USING itm.dem_id;
    END IF;
    IF v_fg_id IS NULL THEN
      EXECUTE format('SELECT ft.fg_id FROM %I.feetype ft WHERE ft.feedesc=$1 AND ft.activestatus=1 LIMIT 1',v) INTO v_fg_id USING itm.demfeetype;
    END IF;
    IF v_fg_id IS NULL THEN v_fg_id := 0; END IF;
    IF NOT v_fg_id = ANY(v_fg_ids) THEN v_fg_ids := v_fg_ids || v_fg_id; END IF;
  END LOOP;
  -- Create one payment per fee group
  FOREACH v_fg_id IN ARRAY v_fg_ids LOOP
    v_group_total := 0;
    -- Cash payments auto-reconcile (no bank approval step); others go to pending.
    EXECUTE format('INSERT INTO %I.payment(ins_id,inscode,stu_id,yr_id,yrlabel,transtotalamount,transcurrency,paydate,paystatus,paymethod,payreference,createdby,recon_status,reconciled_by,reconciled_date) VALUES($1,$2,$3,$4,$5,0,''INR'',NOW(),''C'',$6,$7,$8,CASE WHEN LOWER($6)=''cash'' THEN ''R'' ELSE ''P'' END,CASE WHEN LOWER($6)=''cash'' THEN $8 ELSE NULL END,CASE WHEN LOWER($6)=''cash'' THEN NOW() ELSE NULL END) RETURNING pay_id',v)
    INTO v_pay_id USING p_ins_id,p_inscode,p_stu_id,p_yr_id,p_yrlabel,p_pay_method,p_pay_reference,p_created_by;
    -- Get sequence for this fee group (with row lock for concurrency)
    v_seq := NULL;
    EXECUTE format('SELECT seq_id,sequid,seqwidth,seqcurno FROM %I.sequence WHERE ins_id=$1 AND fg_id=$2 LIMIT 1 FOR UPDATE',v) INTO v_seq USING p_ins_id,v_fg_id;
    IF v_seq IS NULL THEN v_pay_number:='PAY'||v_pay_id;
    ELSE v_new_no:=v_seq.seqcurno+1; v_pay_number:=regexp_replace(v_seq.sequid,'\d+$','')||lpad(v_new_no::TEXT,v_seq.seqwidth::INTEGER,'0'); EXECUTE format('UPDATE %I.sequence SET seqcurno=$1 WHERE seq_id=$2',v) USING v_new_no,v_seq.seq_id;
    END IF;
    EXECUTE format('UPDATE %I.payment SET paynumber=$1 WHERE pay_id=$2',v) USING v_pay_number,v_pay_id;
    -- Process demands for this fee group
    FOR itm IN SELECT x.dem_id, x.yr_id, x.yrlabel, x.amount, x.demfeetype
      FROM jsonb_to_recordset(p_items) AS x(dem_id bigint, yr_id integer, yrlabel text, ins_id integer, amount numeric, demfeetype text)
    LOOP
      DECLARE v_item_fg INTEGER;
      BEGIN
        v_item_fg := NULL;
        IF itm.demfeetype = 'FINE' THEN
          EXECUTE format($q$
            SELECT ft.fg_id
            FROM %I.feedemand fn
            JOIN %I.feedemand orig ON orig.dem_id = (
              CASE
                WHEN position('-' in substring(fn.demno from 3)) > 0
                  THEN substring(fn.demno from 3 for position('-' in substring(fn.demno from 3)) - 1)::bigint
                ELSE substring(fn.demno from 3)::bigint
              END
            )
            JOIN %I.feetype ft
              ON (orig.fee_id IS NOT NULL AND ft.fee_id = orig.fee_id)
              OR (orig.fee_id IS NULL AND ft.feedesc = orig.demfeetype)
            WHERE fn.dem_id = $1 AND ft.activestatus = 1
            LIMIT 1
          $q$, v, v, v) INTO v_item_fg USING itm.dem_id;
        END IF;
        IF v_item_fg IS NULL THEN
          EXECUTE format('SELECT ft.fg_id FROM %I.feetype ft WHERE ft.feedesc=$1 AND ft.activestatus=1 LIMIT 1',v) INTO v_item_fg USING itm.demfeetype;
        END IF;
        IF v_item_fg IS NULL THEN v_item_fg := 0; END IF;
        IF v_item_fg != v_fg_id THEN CONTINUE; END IF;
      END;
      v_group_total := v_group_total + itm.amount;
      EXECUTE format('INSERT INTO %I.paymentdetails(pay_id,dem_id,yr_id,yrlabel,ins_id,transcurrency,transtotalamount) VALUES($1,$2,$3,$4,$5,''INR'',$6)',v) USING v_pay_id,itm.dem_id,itm.yr_id,itm.yrlabel,p_ins_id,itm.amount;
      -- FOR UPDATE locks the row so concurrent collectors serialize. If the
      -- locked balance is already <= 0 another accountant got here first;
      -- raise to roll back this whole txn (including the payment row inserted
      -- above) so no duplicate receipt is created.
      EXECUTE format('SELECT paidamount,balancedue FROM %I.feedemand WHERE dem_id=$1 AND activestatus=1 FOR UPDATE',v) INTO v_current_paid,v_current_balance USING itm.dem_id;
      IF COALESCE(v_current_balance,0) <= 0 THEN
        RAISE EXCEPTION 'Demand % is already paid (balance=%). Another payment may have been posted - please refresh.', itm.dem_id, v_current_balance USING ERRCODE = 'P0001';
      END IF;
      v_new_paid:=COALESCE(v_current_paid,0)+itm.amount; v_new_balance:=COALESCE(v_current_balance,0)-itm.amount; IF v_new_balance<0 THEN v_new_balance:=0; END IF;
      -- For cash (auto-reconciled) payments, also sync reconbalancedue so
      -- the Pending Payment Report doesn't leave them as owed.
      IF LOWER(p_pay_method) = 'cash' THEN
        EXECUTE format('UPDATE %I.feedemand SET paidamount=$1,balancedue=$2,reconbalancedue=$2,paidstatus=CASE WHEN $2<=0 THEN ''P'' ELSE ''U'' END,pay_id=$3 WHERE dem_id=$4',v) USING v_new_paid,v_new_balance,v_pay_id,itm.dem_id;
      ELSE
        EXECUTE format('UPDATE %I.feedemand SET paidamount=$1,balancedue=$2,paidstatus=CASE WHEN $2<=0 THEN ''P'' ELSE ''U'' END,pay_id=$3 WHERE dem_id=$4',v) USING v_new_paid,v_new_balance,v_pay_id,itm.dem_id;
      END IF;
    END LOOP;
    EXECUTE format('UPDATE %I.payment SET transtotalamount=$1 WHERE pay_id=$2',v) USING v_group_total,v_pay_id;
    v_result := v_result || jsonb_build_object('pay_id',v_pay_id,'paynumber',v_pay_number,'fg_id',v_fg_id,'amount',v_group_total);
  END LOOP;
  RETURN v_result;
END; $$;

-- 4. Complete payment grouped (splits I record into per-group C/F records, for Razorpay)
CREATE OR REPLACE FUNCTION public.complete_payment_grouped(
  p_pay_id bigint, p_pay_method text, p_pay_reference text,
  p_items jsonb, p_ins_id integer, p_status char DEFAULT 'C'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v text; v_fg_id INTEGER; v_new_pay_id BIGINT; v_pay_number TEXT;
  v_seq RECORD; v_new_no INTEGER;
  v_current_paid NUMERIC; v_current_balance NUMERIC;
  v_new_paid NUMERIC; v_new_balance NUMERIC;
  v_result JSONB := '[]'::jsonb;
  v_group_total NUMERIC;
  v_orig RECORD;
  itm RECORD; v_fg_ids INTEGER[];
BEGIN
  v := get_institution_schema(p_ins_id);
  IF v IS NULL THEN RAISE EXCEPTION 'No schema found'; END IF;
  -- Get original payment info. FOR UPDATE locks the row so a concurrent call
  -- for the same p_pay_id blocks here, then finds it gone after the DELETE
  -- below — prevents duplicate receipts / double-decremented feedemand.
  EXECUTE format('SELECT ins_id,inscode,stu_id,yr_id,yrlabel,createdby,payorderid,payreference FROM %I.payment WHERE pay_id=$1 FOR UPDATE',v) INTO v_orig USING p_pay_id;
  IF v_orig IS NULL THEN RAISE EXCEPTION 'Payment % not found',p_pay_id; END IF;
  -- Empty p_items = finalize the existing row in place (failure path from the
  -- mobile app passes []). The original split-by-fee-group logic below would
  -- DELETE the row and create nothing in its place, causing the failed record
  -- to vanish — so short-circuit here.
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    EXECUTE format('UPDATE %I.payment SET paystatus=$1, paymethod=$2, payreference=COALESCE($3, payreference), paydate=NOW() WHERE pay_id=$4',v)
      USING p_status, p_pay_method, p_pay_reference, p_pay_id;
    RETURN jsonb_build_array(jsonb_build_object('pay_id', p_pay_id, 'paynumber', NULL, 'fg_id', NULL, 'amount', 0));
  END IF;
  -- Collect distinct fee groups
  v_fg_ids := ARRAY[]::INTEGER[];
  FOR itm IN SELECT x.dem_id, x.amount, x.demfeetype
    FROM jsonb_to_recordset(p_items) AS x(dem_id bigint, amount numeric, demfeetype text)
  LOOP
    v_fg_id := NULL;
    EXECUTE format('SELECT ft.fg_id FROM %I.feetype ft WHERE ft.feedesc=$1 AND ft.activestatus=1 LIMIT 1',v) INTO v_fg_id USING itm.demfeetype;
    IF v_fg_id IS NULL THEN v_fg_id := 0; END IF;
    IF NOT v_fg_id = ANY(v_fg_ids) THEN v_fg_ids := v_fg_ids || v_fg_id; END IF;
  END LOOP;
  -- Delete original I payment
  EXECUTE format('DELETE FROM %I.paymentdetails WHERE pay_id=$1',v) USING p_pay_id;
  EXECUTE format('DELETE FROM %I.payment WHERE pay_id=$1',v) USING p_pay_id;
  -- Create per-group payments
  FOREACH v_fg_id IN ARRAY v_fg_ids LOOP
    v_group_total := 0;
    v_pay_number := NULL;
    EXECUTE format('INSERT INTO %I.payment(ins_id,inscode,stu_id,yr_id,yrlabel,transtotalamount,transcurrency,paydate,paystatus,paymethod,payreference,createdby,payorderid,recon_status) VALUES($1,$2,$3,$4,$5,0,''INR'',NOW(),$6,$7,$8,$9,$10,''P'') RETURNING pay_id',v)
    INTO v_new_pay_id USING v_orig.ins_id,v_orig.inscode,v_orig.stu_id,v_orig.yr_id,v_orig.yrlabel,p_status,p_pay_method,p_pay_reference,v_orig.createdby,v_orig.payorderid;
    -- Paynumber + sequence are reserved for successful payments only.
    -- Failed/cancelled payments stay with paynumber=NULL so we don't burn a
    -- receipt number on a transaction that never settled.
    IF p_status = 'C' THEN
      v_seq := NULL;
      EXECUTE format('SELECT seq_id,sequid,seqwidth,seqcurno FROM %I.sequence WHERE ins_id=$1 AND fg_id=$2 LIMIT 1 FOR UPDATE',v) INTO v_seq USING p_ins_id,v_fg_id;
      IF v_seq IS NULL THEN v_pay_number:='PAY'||v_new_pay_id;
      ELSE v_new_no:=v_seq.seqcurno+1; v_pay_number:=regexp_replace(v_seq.sequid,'\d+$','')||lpad(v_new_no::TEXT,v_seq.seqwidth::INTEGER,'0'); EXECUTE format('UPDATE %I.sequence SET seqcurno=$1 WHERE seq_id=$2',v) USING v_new_no,v_seq.seq_id;
      END IF;
      EXECUTE format('UPDATE %I.payment SET paynumber=$1 WHERE pay_id=$2',v) USING v_pay_number,v_new_pay_id;
    END IF;
    -- Process demands
    FOR itm IN SELECT x.dem_id, x.amount, x.demfeetype
      FROM jsonb_to_recordset(p_items) AS x(dem_id bigint, amount numeric, demfeetype text)
    LOOP
      DECLARE v_item_fg INTEGER;
      BEGIN
        EXECUTE format('SELECT ft.fg_id FROM %I.feetype ft WHERE ft.feedesc=$1 AND ft.activestatus=1 LIMIT 1',v) INTO v_item_fg USING itm.demfeetype;
        IF v_item_fg IS NULL THEN v_item_fg := 0; END IF;
        IF v_item_fg != v_fg_id THEN CONTINUE; END IF;
      END;
      v_group_total := v_group_total + itm.amount;
      EXECUTE format('INSERT INTO %I.paymentdetails(pay_id,dem_id,yr_id,yrlabel,ins_id,transcurrency,transtotalamount) VALUES($1,$2,$3,$4,$5,''INR'',$6)',v) USING v_new_pay_id,itm.dem_id,v_orig.yr_id,v_orig.yrlabel,p_ins_id,itm.amount;
      -- Update feedemand only if success. Atomic read-modify-write via the
      -- UPDATE itself — no separate SELECT. Safe against concurrent payments
      -- targeting the same dem_id (Postgres row-locks during UPDATE).
      IF p_status = 'C' THEN
        EXECUTE format('UPDATE %I.feedemand
                          SET paidamount = COALESCE(paidamount, 0) + $1,
                              balancedue = GREATEST(COALESCE(balancedue, 0) - $1, 0),
                              paidstatus = CASE WHEN GREATEST(COALESCE(balancedue, 0) - $1, 0) <= 0 THEN ''P'' ELSE ''U'' END,
                              pay_id     = $2
                          WHERE dem_id = $3 AND activestatus = 1', v)
        USING itm.amount, v_new_pay_id, itm.dem_id;
      END IF;
    END LOOP;
    EXECUTE format('UPDATE %I.payment SET transtotalamount=$1 WHERE pay_id=$2',v) USING v_group_total,v_new_pay_id;
    v_result := v_result || jsonb_build_object('pay_id',v_new_pay_id,'paynumber',v_pay_number,'fg_id',v_fg_id,'amount',v_group_total);
  END LOOP;
  RETURN v_result;
END; $$;

-- 5. Active cart fees (mobile app cart restore)
-- Returns the feedemand rows in the student's active (carinitiated='N') cart
-- as a JSON array. Scans institution schemas; returns on first hit.
CREATE OR REPLACE FUNCTION public.get_active_cart_fees(p_stu_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
DECLARE
  v_schema text;
  v_result jsonb;
BEGIN
  FOR v_schema IN
    SELECT n.nspname FROM pg_namespace n
    WHERE n.nspname NOT IN ('public','pg_catalog','information_schema','pg_toast','auth','storage','realtime','supabase_functions','graphql','graphql_public','extensions','pgsodium','pgsodium_masks','vault','net','cron')
      AND EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n2 ON n2.oid = c.relnamespace WHERE n2.nspname = n.nspname AND c.relname = 'shoppingcart')
  LOOP
    EXECUTE format($q$
      SELECT COALESCE(jsonb_agg(to_jsonb(fd.*)), '[]'::jsonb)
      FROM %1$I.shoppingcart sc
      JOIN %1$I.shoppingcartdetails scd ON scd.car_id = sc.car_id AND scd.activestatus = 1
      JOIN %1$I.feedemand fd ON fd.dem_id = scd.dem_id AND fd.activestatus = 1
      WHERE sc.stu_id = $1 AND sc.carinitiated = 'N' AND sc.activestatus = 1
    $q$, v_schema) INTO v_result USING p_stu_id;
    IF v_result IS NOT NULL AND jsonb_array_length(v_result) > 0 THEN
      RETURN v_result;
    END IF;
  END LOOP;
  RETURN '[]'::jsonb;
END; $$;
GRANT EXECUTE ON FUNCTION public.get_active_cart_fees(bigint) TO anon, authenticated;

-- ============================================
-- OVERDUE FINE GENERATION
-- ============================================
-- For each unpaid demand whose fee type has feefineapplicable = 1 AND whose
-- classfeedemand.cfdduedate is in the past, looks up the matching fine rule
-- and creates a FINE demand row in feedemand (paidstatus='U', balancedue=fine).
-- Idempotent — safe to call repeatedly. Called from the Flutter app on every
-- successful institution login.

CREATE OR REPLACE FUNCTION public.generate_overdue_fines(p_ins_id integer)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_schema text;
  v_changes int := 0;
BEGIN
  v_schema := get_institution_schema(p_ins_id);
  IF v_schema IS NULL THEN RETURN 0; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema = v_schema AND table_name = 'finerule') THEN
    RETURN 0;
  END IF;

  -- Update fineamount on each unpaid, fine-applicable, overdue demand to
  -- match the current applicable fine slab. Uses feedemand.duedate directly
  -- as the source of truth. Fine is stored INLINE on the original demand row
  -- (no separate FINE demand row).
  EXECUTE format($f$
    WITH per_demand AS (
      SELECT
        fd.dem_id, fd.feeamount, fd.demfeetype,
        COALESCE(fd.fineamount, 0) AS current_fine,
        (CURRENT_DATE - fd.duedate)::int AS overdue_days
      FROM %1$I.feedemand fd
      JOIN %1$I.feetype ft
        ON (
             (fd.fee_id IS NOT NULL AND ft.fee_id = fd.fee_id)
             OR (fd.fee_id IS NULL AND ft.feedesc = fd.demfeetype)
           )
       AND ft.activestatus = 1
       AND COALESCE(ft.feefineapplicable, 0) = 1
      WHERE fd.ins_id = $1
        AND fd.activestatus = 1
        AND fd.demfeetype <> 'FINE'
        AND fd.balancedue > 0
        AND fd.duedate IS NOT NULL
        AND fd.duedate < CURRENT_DATE
    ),
    target AS (
      SELECT pd.dem_id, pd.current_fine,
        (SELECT CASE WHEN r.fine_type = 'PERCENT'
                     THEN ROUND(pd.feeamount * r.fine_value / 100, 2)
                     ELSE r.fine_value END
         FROM %1$I.finerule r
         WHERE r.ins_id = $1
           AND r.activestatus = 1
           AND pd.overdue_days >= r.from_days
           AND (r.to_days IS NULL OR pd.overdue_days <= r.to_days)
           AND (r.feetype = pd.demfeetype OR r.feetype = 'ALL')
         ORDER BY CASE WHEN r.feetype = pd.demfeetype THEN 0 ELSE 1 END,
                  r.from_days DESC
         LIMIT 1) AS target_fine
      FROM per_demand pd
    ),
    delta AS (
      SELECT dem_id, COALESCE(target_fine, 0) AS new_fine
      FROM target
      WHERE COALESCE(target_fine, 0) > current_fine
    )
    UPDATE %1$I.feedemand fd
    SET fineamount = d.new_fine
    FROM delta d
    WHERE fd.dem_id = d.dem_id
  $f$, v_schema) USING p_ins_id;

  GET DIAGNOSTICS v_changes = ROW_COUNT;
  RETURN v_changes;
END; $$;

-- Per-student variant: only refreshes fines for one student's demands.
-- Called from the fee-collection screen when a cashier looks up a student,
-- so the fine column is only computed when the student actually comes to pay.
CREATE OR REPLACE FUNCTION public.generate_overdue_fines_for_student(
  p_ins_id integer,
  p_stuadmno varchar
)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_schema text;
  v_changes int := 0;
BEGIN
  v_schema := get_institution_schema(p_ins_id);
  IF v_schema IS NULL THEN RETURN 0; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema = v_schema AND table_name = 'finerule') THEN
    RETURN 0;
  END IF;

  EXECUTE format($f$
    WITH per_demand AS (
      SELECT
        fd.dem_id, fd.feeamount, fd.demfeetype,
        COALESCE(fd.fineamount, 0) AS current_fine,
        (CURRENT_DATE - fd.duedate)::int AS overdue_days
      FROM %1$I.feedemand fd
      JOIN %1$I.feetype ft
        ON (
             (fd.fee_id IS NOT NULL AND ft.fee_id = fd.fee_id)
             OR (fd.fee_id IS NULL AND ft.feedesc = fd.demfeetype)
           )
       AND ft.activestatus = 1
       AND COALESCE(ft.feefineapplicable, 0) = 1
      WHERE fd.ins_id = $1
        AND fd.stuadmno = $2
        AND fd.activestatus = 1
        AND fd.demfeetype <> 'FINE'
        AND fd.balancedue > 0
        AND fd.duedate IS NOT NULL
        AND fd.duedate < CURRENT_DATE
    ),
    target AS (
      SELECT pd.dem_id, pd.current_fine,
        (SELECT CASE WHEN r.fine_type = 'PERCENT'
                     THEN ROUND(pd.feeamount * r.fine_value / 100, 2)
                     ELSE r.fine_value END
         FROM %1$I.finerule r
         WHERE r.ins_id = $1
           AND r.activestatus = 1
           AND pd.overdue_days >= r.from_days
           AND (r.to_days IS NULL OR pd.overdue_days <= r.to_days)
           AND (r.feetype = pd.demfeetype OR r.feetype = 'ALL')
         ORDER BY CASE WHEN r.feetype = pd.demfeetype THEN 0 ELSE 1 END,
                  r.from_days DESC
         LIMIT 1) AS target_fine
      FROM per_demand pd
    ),
    delta AS (
      SELECT dem_id, COALESCE(target_fine, 0) AS new_fine
      FROM target
      WHERE COALESCE(target_fine, 0) > current_fine
    )
    UPDATE %1$I.feedemand fd
    SET fineamount = d.new_fine
    FROM delta d
    WHERE fd.dem_id = d.dem_id
  $f$, v_schema) USING p_ins_id, p_stuadmno;

  GET DIAGNOSTICS v_changes = ROW_COUNT;
  RETURN v_changes;
END; $$;

CREATE OR REPLACE FUNCTION public.generate_overdue_fines_all()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  rec RECORD;
  v_total int := 0;
  v_count int;
BEGIN
  FOR rec IN SELECT ins_id FROM public.institution WHERE activestatus = 1 LOOP
    v_count := public.generate_overdue_fines(rec.ins_id);
    v_total := v_total + COALESCE(v_count, 0);
  END LOOP;
  RETURN v_total;
END; $$;

-- ============================================
-- PERMISSIONS
-- ============================================
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated;
NOTIFY pgrst, 'reload config';

-- ============================================
-- SEED DATA — institution types (required for registration form)
-- ============================================
INSERT INTO public.institutiontype (ittype, activestatus) VALUES
  ('Schools',     1),
  ('Colleges',    1),
  ('Universities',1),
  ('Polytechnic', 1),
  ('Vocational',  1),
  ('Coaching',    1)
ON CONFLICT (ittype) DO NOTHING;

-- ============================================
-- SEED DATA — super admin user
-- Default credentials: admin / admin123
-- CHANGE THE PASSWORD IMMEDIATELY AFTER FIRST LOGIN.
-- ============================================
INSERT INTO public.staffdesignation (ins_id, desname, activestatus)
SELECT 0, 'Super Admin', 1
WHERE NOT EXISTS (SELECT 1 FROM public.staffdesignation WHERE desname = 'Super Admin' AND ins_id = 0);

INSERT INTO public.custuserroles (ins_id, inscode, urname, activestatus)
SELECT 0, 'SUPER', 'Super Admin', 1
WHERE NOT EXISTS (SELECT 1 FROM public.custuserroles WHERE urname = 'Super Admin' AND inscode = 'SUPER');

INSERT INTO public.institutionusers
  (ins_id, inscode, usename, usemail, usephone, usepassword, usestadate, useotpstatus,
   usedob, ur_id, urname, des_id, desname, userepto, activestatus)
SELECT
  NULL, 'SUPER', 'admin', 'admin@example.com', '0000000000',
  crypt('admin123', gen_salt('bf', 10)),
  CURRENT_DATE, 0, '2000-01-01',
  (SELECT ur_id FROM public.custuserroles WHERE inscode = 'SUPER' AND urname = 'Super Admin' LIMIT 1),
  'Super Admin',
  (SELECT des_id FROM public.staffdesignation WHERE desname = 'Super Admin' AND ins_id = 0 LIMIT 1),
  'Super Admin', 0, 1
WHERE NOT EXISTS (SELECT 1 FROM public.institutionusers WHERE usename = 'admin' AND inscode = 'SUPER');

-- ============================================
-- IMPORTANT: AFTER EACH INSTITUTION REGISTRATION
-- ============================================
-- The app auto-creates the schema (e.g. kcet20262027) with all tables.
-- The register_institution RPC and the Flutter app try to expose it via
-- ALTER ROLE authenticator SET pgrst.db_schemas. On Supabase free tier this
-- requires elevated privilege; if it fails silently, manually run:
--
--   ALTER ROLE authenticator SET pgrst.db_schemas = 'public, schema1, schema2';
--   NOTIFY pgrst, 'reload config';
--
-- Add ALL institution schema names separated by commas.
-- ============================================
-- ════════════════════════════════════════════════════════════════
-- REPORT RPCs (move heavy aggregation into Postgres so the Reports
-- tab loads instantly instead of hanging while Flutter pivots).
--
-- Pass the tenant schema name from the client (SupabaseService.currentSchema).
-- ════════════════════════════════════════════════════════════════

-- 1. DAILY COLLECTION  (receipt-wise pivot)
DROP FUNCTION IF EXISTS public.get_daily_collection_report(TEXT, INT, DATE, DATE);
CREATE OR REPLACE FUNCTION public.get_daily_collection_report(
    p_schema TEXT, p_ins_id INT, p_from DATE, p_to DATE
) RETURNS TABLE (
    pay_id BIGINT, paynumber TEXT, stuadmno TEXT, stuname TEXT,
    courname TEXT, stuclass TEXT, paymethod TEXT, createdby TEXT,
    fees_json JSONB, fine NUMERIC, total NUMERIC, paydate DATE
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY EXECUTE format($f$
        SELECT  p.pay_id::BIGINT,
                p.paynumber::TEXT,
                s.stuadmno::TEXT,
                s.stuname::TEXT,
                s.courname::TEXT,
                s.stuclass::TEXT,
                p.paymethod::TEXT,
                COALESCE(p.createdby, '')::TEXT AS createdby,
