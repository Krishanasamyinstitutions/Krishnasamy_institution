-- Down-migration: undoes everything fee_audit_log.sql and
-- money_grade_fee_collection.sql installed. Restores process_grouped_payment
-- to its previous shape (sequence-first, no fine_captured insert) and
-- complete_payment_grouped to its previous shape (no fine_captured).
-- Run this only if you actually applied the money-grade migrations and
-- want them gone.

-- 1. Drop audit trigger from every per-institution feedemand and the
--    public-side helpers.
DO $mig$
DECLARE rec RECORD;
BEGIN
  FOR rec IN
    SELECT table_schema AS s
    FROM information_schema.tables
    WHERE table_name = 'feedemand'
      AND table_schema NOT IN ('public','pg_catalog','information_schema',
                               'storage','auth','realtime',
                               'supabase_functions','extensions')
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_feedemand_audit ON %I.feedemand', rec.s);
  END LOOP;
END;
$mig$;

DROP FUNCTION IF EXISTS public.feedemand_audit_trg();
DROP TABLE IF EXISTS public.feedemand_audit;

-- 2. Drop the receipt RPC.
DROP FUNCTION IF EXISTS public.atomic_receipt_data(integer, bigint);

-- 3. Drop the fine_captured column from every per-institution
--    paymentdetails. Data in that column is gone — make sure you've
--    captured what you need first.
DO $mig$
DECLARE rec RECORD;
BEGIN
  FOR rec IN
    SELECT table_schema AS s
    FROM information_schema.tables
    WHERE table_name = 'paymentdetails'
      AND table_schema NOT IN ('public','pg_catalog','information_schema',
                               'storage','auth','realtime',
                               'supabase_functions','extensions')
  LOOP
    EXECUTE format('ALTER TABLE %I.paymentdetails DROP COLUMN IF EXISTS fine_captured', rec.s);
  END LOOP;
END;
$mig$;

-- 4. Restore process_grouped_payment to its pre-money-grade shape.
--    This is the version with the FOR-UPDATE lock from
--    prevent_duplicate_payments.sql but without the sequence-after-update
--    restructure or fine_captured insert.
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
  FOREACH v_fg_id IN ARRAY v_fg_ids LOOP
    v_group_total := 0;
    EXECUTE format('INSERT INTO %I.payment(ins_id,inscode,stu_id,yr_id,yrlabel,transtotalamount,transcurrency,paydate,paystatus,paymethod,payreference,createdby,recon_status,reconciled_by,reconciled_date) VALUES($1,$2,$3,$4,$5,0,''INR'',NOW(),''C'',$6,$7,$8,CASE WHEN LOWER($6)=''cash'' THEN ''R'' ELSE ''P'' END,CASE WHEN LOWER($6)=''cash'' THEN $8 ELSE NULL END,CASE WHEN LOWER($6)=''cash'' THEN NOW() ELSE NULL END) RETURNING pay_id',v)
    INTO v_pay_id USING p_ins_id,p_inscode,p_stu_id,p_yr_id,p_yrlabel,p_pay_method,p_pay_reference,p_created_by;
    v_seq := NULL;
    EXECUTE format('SELECT seq_id,sequid,seqwidth,seqcurno FROM %I.sequence WHERE ins_id=$1 AND fg_id=$2 LIMIT 1 FOR UPDATE',v) INTO v_seq USING p_ins_id,v_fg_id;
    IF v_seq IS NULL THEN v_pay_number:='PAY'||v_pay_id;
    ELSE v_new_no:=v_seq.seqcurno+1; v_pay_number:=regexp_replace(v_seq.sequid,'\d+$','')||lpad(v_new_no::TEXT,v_seq.seqwidth::INTEGER,'0'); EXECUTE format('UPDATE %I.sequence SET seqcurno=$1 WHERE seq_id=$2',v) USING v_new_no,v_seq.seq_id;
    END IF;
    EXECUTE format('UPDATE %I.payment SET paynumber=$1 WHERE pay_id=$2',v) USING v_pay_number,v_pay_id;
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
      EXECUTE format('SELECT paidamount,balancedue FROM %I.feedemand WHERE dem_id=$1 AND activestatus=1 FOR UPDATE',v) INTO v_current_paid,v_current_balance USING itm.dem_id;
      IF COALESCE(v_current_balance,0) <= 0 THEN
        RAISE EXCEPTION 'Demand % is already paid (balance=%). Another payment may have been posted - please refresh.', itm.dem_id, v_current_balance USING ERRCODE = 'P0001';
      END IF;
      v_new_paid:=COALESCE(v_current_paid,0)+itm.amount; v_new_balance:=COALESCE(v_current_balance,0)-itm.amount; IF v_new_balance<0 THEN v_new_balance:=0; END IF;
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

-- 5. Restore complete_payment_grouped to the pre-money-grade shape.
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
  EXECUTE format('SELECT ins_id,inscode,stu_id,yr_id,yrlabel,createdby,payorderid,payreference FROM %I.payment WHERE pay_id=$1 FOR UPDATE',v) INTO v_orig USING p_pay_id;
  IF v_orig IS NULL THEN RAISE EXCEPTION 'Payment % not found',p_pay_id; END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    EXECUTE format('UPDATE %I.payment SET paystatus=$1, paymethod=$2, payreference=COALESCE($3, payreference), paydate=NOW() WHERE pay_id=$4',v)
      USING p_status, p_pay_method, p_pay_reference, p_pay_id;
    RETURN jsonb_build_array(jsonb_build_object('pay_id', p_pay_id, 'paynumber', NULL, 'fg_id', NULL, 'amount', 0));
  END IF;
  v_fg_ids := ARRAY[]::INTEGER[];
  FOR itm IN SELECT x.dem_id, x.amount, x.demfeetype
    FROM jsonb_to_recordset(p_items) AS x(dem_id bigint, amount numeric, demfeetype text)
  LOOP
    v_fg_id := NULL;
    EXECUTE format('SELECT ft.fg_id FROM %I.feetype ft WHERE ft.feedesc=$1 AND ft.activestatus=1 LIMIT 1',v) INTO v_fg_id USING itm.demfeetype;
    IF v_fg_id IS NULL THEN v_fg_id := 0; END IF;
    IF NOT v_fg_id = ANY(v_fg_ids) THEN v_fg_ids := v_fg_ids || v_fg_id; END IF;
  END LOOP;
  EXECUTE format('DELETE FROM %I.paymentdetails WHERE pay_id=$1',v) USING p_pay_id;
  EXECUTE format('DELETE FROM %I.payment WHERE pay_id=$1',v) USING p_pay_id;
  FOREACH v_fg_id IN ARRAY v_fg_ids LOOP
    v_group_total := 0;
    v_pay_number := NULL;
    EXECUTE format('INSERT INTO %I.payment(ins_id,inscode,stu_id,yr_id,yrlabel,transtotalamount,transcurrency,paydate,paystatus,paymethod,payreference,createdby,payorderid,recon_status) VALUES($1,$2,$3,$4,$5,0,''INR'',NOW(),$6,$7,$8,$9,$10,''P'') RETURNING pay_id',v)
    INTO v_new_pay_id USING v_orig.ins_id,v_orig.inscode,v_orig.stu_id,v_orig.yr_id,v_orig.yrlabel,p_status,p_pay_method,p_pay_reference,v_orig.createdby,v_orig.payorderid;
    IF p_status = 'C' THEN
      v_seq := NULL;
      EXECUTE format('SELECT seq_id,sequid,seqwidth,seqcurno FROM %I.sequence WHERE ins_id=$1 AND fg_id=$2 LIMIT 1 FOR UPDATE',v) INTO v_seq USING p_ins_id,v_fg_id;
      IF v_seq IS NULL THEN v_pay_number:='PAY'||v_new_pay_id;
      ELSE v_new_no:=v_seq.seqcurno+1; v_pay_number:=regexp_replace(v_seq.sequid,'\d+$','')||lpad(v_new_no::TEXT,v_seq.seqwidth::INTEGER,'0'); EXECUTE format('UPDATE %I.sequence SET seqcurno=$1 WHERE seq_id=$2',v) USING v_new_no,v_seq.seq_id;
      END IF;
      EXECUTE format('UPDATE %I.payment SET paynumber=$1 WHERE pay_id=$2',v) USING v_pay_number,v_new_pay_id;
    END IF;
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
