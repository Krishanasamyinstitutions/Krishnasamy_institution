-- Add reconbalancedue to get_fee_demands so the Class-wise Demand tab can mark
-- rows as Paid only after the payment is reconciled with the bank statement.

CREATE OR REPLACE FUNCTION public.get_fee_demands(p_ins_id integer) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v text; r json;
BEGIN
  v := get_institution_schema(p_ins_id);
  IF v IS NULL THEN RETURN NULL; END IF;
  EXECUTE format(
    'SELECT json_agg(json_build_object('
    '''dem_id'',fd.dem_id,''fee_id'',fd.fee_id,''ins_id'',fd.ins_id,'
    '''stu_id'',fd.stu_id,''feeamount'',fd.feeamount,''conamount'',fd.conamount,'
    '''paidamount'',fd.paidamount,''fineamount'',fd.fineamount,'
    '''duedate'',fd.duedate,''paidstatus'',fd.paidstatus,'
    '''stuclass'',fd.stuclass,''courname'',fd.courname,'
    '''stuadmno'',fd.stuadmno,''demfeetype'',fd.demfeetype,'
    '''demfeeterm'',fd.demfeeterm,''balancedue'',fd.balancedue,'
    '''reconbalancedue'',fd.reconbalancedue,'
    '''stuname'',s.stuname) ORDER BY fd.courname,fd.stuclass) '
    'FROM %I.feedemand fd LEFT JOIN %I.students s ON s.stu_id=fd.stu_id '
    'WHERE fd.ins_id=$1 AND fd.activestatus=1', v, v
  ) INTO r USING p_ins_id;
  RETURN r;
END; $$;
