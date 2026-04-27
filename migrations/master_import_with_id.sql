-- Master-import rule:
--   * ID present in col1 → INSERT with that exact id.
--   * ID missing/invalid → reject row (no sequence fallback).
--   * ID collides with an existing row → reject that row (duplicate key).
-- No upsert, no auto-generate. The import is the definitive source of ids.
--
-- Apply AFTER master_id_sequences.sql.

CREATE OR REPLACE FUNCTION public.process_master_import(p_ins_id integer) RETURNS TABLE(total integer, imported integer, skipped integer)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    rec RECORD;
    v_total int := 0;
    v_imported int := 0;
    v_skipped int := 0;
    v_fg_id int;
    v_schema text;
    v_id int;
BEGIN
    v_schema := get_institution_schema(p_ins_id);
    FOR rec IN SELECT * FROM master_import WHERE ins_id = p_ins_id AND status = 'PENDING' ORDER BY imp_id LOOP
        v_total := v_total + 1;
        BEGIN
            -- Reject rows missing an id in col1.
            IF rec.col1 IS NULL OR TRIM(rec.col1) = '' THEN
                UPDATE master_import SET status = 'ERROR', error_msg = 'Missing id in column 1' WHERE imp_id = rec.imp_id;
                v_skipped := v_skipped + 1;
                CONTINUE;
            END IF;
            BEGIN
                v_id := TRIM(rec.col1)::int;
            EXCEPTION WHEN OTHERS THEN
                UPDATE master_import SET status = 'ERROR', error_msg = 'Invalid id: "'||rec.col1||'"' WHERE imp_id = rec.imp_id;
                v_skipped := v_skipped + 1;
                CONTINUE;
            END;

            IF v_schema IS NULL THEN
                UPDATE master_import SET status = 'ERROR', error_msg = 'No institution schema' WHERE imp_id = rec.imp_id;
                v_skipped := v_skipped + 1;
                CONTINUE;
            END IF;

            CASE rec.imp_type
            WHEN 'FEEGROUP' THEN
                -- col2=desc, col3=yrlabel, col4=ban_id
                EXECUTE format($ins$
                    INSERT INTO %I.feegroup(fg_id, fgdesc, ins_id, yr_id, yrlabel, ban_id, activestatus)
                    VALUES ($1, $2, $3, 0, COALESCE($4, ''), NULLIF($5, '')::int, 1)
                $ins$, v_schema) USING v_id, TRIM(rec.col2), p_ins_id, TRIM(rec.col3), TRIM(rec.col4);

            WHEN 'FEETYPE' THEN
                -- col2=desc, col3=short, col4=fg_name, col5=yrlabel, col6=optional, col7=category, col8=fine
                EXECUTE format('SELECT fg_id FROM %I.feegroup WHERE UPPER(TRIM(fgdesc))=UPPER($1) AND ins_id=$2 AND activestatus=1 LIMIT 1', v_schema)
                    INTO v_fg_id USING TRIM(rec.col4), p_ins_id;
                IF v_fg_id IS NULL THEN
                    UPDATE master_import SET status = 'ERROR', error_msg = 'Fee group "'||rec.col4||'" not found' WHERE imp_id = rec.imp_id;
                    v_skipped := v_skipped + 1;
                    CONTINUE;
                END IF;
                EXECUTE format($ins$
                    INSERT INTO %I.feetype(fee_id, feedesc, feeshort, fg_id, yr_id, yrlabel, feeoptional, feecategory, feefineapplicable, activestatus, ins_id)
                    VALUES ($1, $2, $3, $4, 0, COALESCE($5, ''),
                            NULLIF($6, '')::smallint,
                            NULLIF($7, '')::smallint,
                            COALESCE(NULLIF($8, '')::smallint, 0),
                            1, $9)
                $ins$, v_schema) USING v_id, TRIM(rec.col2), TRIM(rec.col3), v_fg_id, TRIM(rec.col5), TRIM(rec.col6), TRIM(rec.col7), TRIM(rec.col8), p_ins_id;

            WHEN 'CONCESSION' THEN
                -- col2=desc, col3=ordid
                EXECUTE format($ins$
                    INSERT INTO %I.concessioncategory(con_id, condesc, ins_id, ordid, activestatus)
                    VALUES ($1, $2, $3, NULLIF($4, '')::int, 1)
                $ins$, v_schema) USING v_id, TRIM(rec.col2), p_ins_id, TRIM(rec.col3);

            WHEN 'CLASSFEEDEMAND' THEN
                -- col2=class, col3=term, col4=feetype, col5=amount, col6=duedate, col7=admtype
                EXECUTE format($ins$
                    INSERT INTO %I.classfeedemand(cf_id, cfclass, cfterm, cffeetype, cfamount, cfdduedate, admissiontype)
                    VALUES ($1, $2, NULLIF($3, ''), $4,
                            NULLIF($5, '')::numeric(12,2),
                            NULLIF($6, '')::date,
                            NULLIF($7, '')::smallint)
                $ins$, v_schema) USING v_id, TRIM(rec.col2), TRIM(rec.col3), TRIM(rec.col4), TRIM(rec.col5), TRIM(rec.col6), TRIM(rec.col7);

            ELSE
                UPDATE master_import SET status = 'ERROR', error_msg = 'Unknown type: '||rec.imp_type WHERE imp_id = rec.imp_id;
                v_skipped := v_skipped + 1;
                CONTINUE;
            END CASE;

            UPDATE master_import SET status = 'DONE' WHERE imp_id = rec.imp_id;
            v_imported := v_imported + 1;

        EXCEPTION WHEN unique_violation THEN
            -- Friendly duplicate-id message instead of the raw Postgres SQLERRM.
            UPDATE master_import SET status = 'ERROR',
                   error_msg = 'ID '||COALESCE(v_id::text, rec.col1)||' already exists — row rejected'
             WHERE imp_id = rec.imp_id;
            v_skipped := v_skipped + 1;
        WHEN OTHERS THEN
            UPDATE master_import SET status = 'ERROR', error_msg = SQLERRM WHERE imp_id = rec.imp_id;
            v_skipped := v_skipped + 1;
        END;
    END LOOP;

    RETURN QUERY SELECT v_total, v_imported, v_skipped;
END;
$$;
