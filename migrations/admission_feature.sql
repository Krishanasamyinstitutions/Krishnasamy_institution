-- ============================================================================
-- ADMISSION FEATURE — complete, self-contained, idempotent installer.
-- ============================================================================
-- Run this ONCE on any database (fresh or existing) to add the full admission
-- module. Safe to re-run. It installs:
--   1. public.admission        — staging table for new admissions (all fields)
--   2. students columns        — aadharno + demographic/facility columns added
--                                to students in EVERY existing institution schema
--   3. allocate_admission_to_student(...) — moves a PENDING admission into the
--                                schema's students/parents/parentdetail tables
--
-- FUTURE institutions are covered automatically: the allocate RPC self-heals
-- the target schema's `students` table (ADD COLUMN IF NOT EXISTS) before the
-- move, so newly-created schemas never need a manual patch.
-- ============================================================================


-- ===========================================================================
-- 1. public.admission
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.admission (
  adm_id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ins_id          integer       NOT NULL,
  inscode         varchar(10)   NOT NULL,
  yr_id           integer       NOT NULL,
  yrlabel         varchar(9)    NOT NULL,

  -- admission identity / workflow
  admno           varchar(25)   NOT NULL,
  admdate         date          DEFAULT CURRENT_DATE NOT NULL,
  admsource       varchar(30)   DEFAULT 'WALK-IN',
  admstatus       varchar(15)   DEFAULT 'PENDING' NOT NULL
                    CHECK (admstatus = ANY (ARRAY['PENDING','ALLOCATED','CANCELLED'])),
  allocatedclass  varchar(20),
  stu_id          bigint,
  allocatedby     varchar(50),
  allocateddate   timestamp,
  admremarks      text,

  -- student fields (match schema.students column names)
  stuname         varchar(50)   NOT NULL,
  stugender       char(1)       NOT NULL CHECK (stugender = ANY (ARRAY['M','F','T'])),
  studob          date          NOT NULL,
  stumobile       varchar(30),
  stuemail        varchar(254),
  stuaddress      text,
  stucity         varchar(50),
  stustate        varchar(50),
  stucountry      varchar(50),
  stupin          varchar(6),
  stubloodgrp     varchar(20),
  stuphoto        text,
  aadharno        varchar(20),
  courname        varchar(20),
  stuclass        varchar(20),
  admname         varchar(30),
  quoname         varchar(30),
  con_id          integer,
  stucondesc      varchar(20),
  batch           varchar(9),
  admittyear      varchar(9),

  -- demographics / facilities
  community       varchar(30),
  caste           varchar(30),
  religion        varchar(30),
  nationality     varchar(30),
  transportmode   varchar(10),                            -- OWN / COLLEGE
  hostel          char(1),                                -- Y / N

  -- previous academics
  prevschool      varchar(100),
  prevclass       varchar(20),
  prevboard       varchar(50),
  prevpercent     numeric(5,2),

  -- parent / guardian (match schema.parents column names)
  fathername      varchar(50),
  fathermobile    varchar(20),
  fatheroccupation varchar(60),
  mothername      varchar(50),
  mothermobile    varchar(20),
  motheroccupation varchar(60),
  guardianname    varchar(50),
  guardianmobile  varchar(20),
  guardianoccupation varchar(60),
  payincharge     varchar(50),
  payinchargemob  varchar(20),

  createdby       varchar(50),
  createdon       timestamp     DEFAULT now() NOT NULL,
  activestatus    smallint      DEFAULT 1 NOT NULL CHECK (activestatus = ANY (ARRAY[1,9]))
);

-- Upgrade path: if an older public.admission already existed, add any columns
-- introduced later (no-op on a fresh create above).
ALTER TABLE public.admission ADD COLUMN IF NOT EXISTS aadharno      varchar(20);
ALTER TABLE public.admission ADD COLUMN IF NOT EXISTS community     varchar(30);
ALTER TABLE public.admission ADD COLUMN IF NOT EXISTS caste         varchar(30);
ALTER TABLE public.admission ADD COLUMN IF NOT EXISTS religion      varchar(30);
ALTER TABLE public.admission ADD COLUMN IF NOT EXISTS nationality   varchar(30);
ALTER TABLE public.admission ADD COLUMN IF NOT EXISTS transportmode varchar(10);
ALTER TABLE public.admission ADD COLUMN IF NOT EXISTS hostel        char(1);
ALTER TABLE public.admission ADD COLUMN IF NOT EXISTS fatheroccupation   varchar(60);
ALTER TABLE public.admission ADD COLUMN IF NOT EXISTS motheroccupation   varchar(60);
ALTER TABLE public.admission ADD COLUMN IF NOT EXISTS guardianoccupation varchar(60);

CREATE UNIQUE INDEX IF NOT EXISTS uq_admission_admno ON public.admission (ins_id, admno);
CREATE INDEX IF NOT EXISTS idx_admission_status ON public.admission (ins_id, admstatus, activestatus);

ALTER TABLE public.admission ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all" ON public.admission;
CREATE POLICY "Allow all" ON public.admission USING (true) WITH CHECK (true);
GRANT ALL ON public.admission TO anon, authenticated;


-- ===========================================================================
-- 2. students columns on every existing institution schema
-- ===========================================================================
DO $$
DECLARE
  r record;
  sname text;
BEGIN
  FOR r IN
    SELECT DISTINCT lower(i.inshortname) || replace(iy.yrlabel, '-', '') AS schema_name
    FROM public.institution i
    JOIN public.institutionyear iy ON iy.ins_id = i.ins_id
    WHERE i.inshortname IS NOT NULL
  LOOP
    sname := r.schema_name;
    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = sname)
       AND EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                   WHERE n.nspname = sname AND c.relname = 'students') THEN
      EXECUTE format('ALTER TABLE %I.students ADD COLUMN IF NOT EXISTS aadharno      varchar(20)', sname);
      EXECUTE format('ALTER TABLE %I.students ADD COLUMN IF NOT EXISTS community     varchar(30)', sname);
      EXECUTE format('ALTER TABLE %I.students ADD COLUMN IF NOT EXISTS caste         varchar(30)', sname);
      EXECUTE format('ALTER TABLE %I.students ADD COLUMN IF NOT EXISTS religion      varchar(30)', sname);
      EXECUTE format('ALTER TABLE %I.students ADD COLUMN IF NOT EXISTS nationality   varchar(30)', sname);
      EXECUTE format('ALTER TABLE %I.students ADD COLUMN IF NOT EXISTS transportmode varchar(10)', sname);
      EXECUTE format('ALTER TABLE %I.students ADD COLUMN IF NOT EXISTS hostel        char(1)', sname);
      -- Community master (lookup for the admission form)
      EXECUTE format(
        'CREATE TABLE IF NOT EXISTS %I.community ('
        'com_id smallint PRIMARY KEY, comname varchar(40) NOT NULL, ins_id integer, '
        'activestatus smallint DEFAULT 1 NOT NULL, createdat timestamp DEFAULT now(), createdby varchar(50))',
        sname);
      EXECUTE format('GRANT ALL ON %I.community TO anon, authenticated', sname);
      -- Register-number sequencing master
      EXECUTE format(
        'CREATE TABLE IF NOT EXISTS %I.regnoseq ('
        'rns_id smallint PRIMARY KEY, rnsname varchar(50) NOT NULL, '
        'rnsmode char(1) DEFAULT ''P'' NOT NULL CHECK (rnsmode IN (''P'',''S'')), '
        'rnsaffix varchar(15), rnsstart numeric(9,0) DEFAULT 1, rnsend numeric(9,0), '
        'rnswidth smallint DEFAULT 4, rnscurrent numeric(9,0) DEFAULT 0, division varchar(50), '
        'ins_id integer, activestatus smallint DEFAULT 1 NOT NULL, '
        'createdat timestamp DEFAULT now(), createdby varchar(50))',
        sname);
      EXECUTE format('GRANT ALL ON %I.regnoseq TO anon, authenticated', sname);
      RAISE NOTICE 'admission_feature: prepared %.students + community + regnoseq', sname;
    END IF;
  END LOOP;
END $$;


-- ===========================================================================
-- 3. allocate_admission_to_student
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.allocate_admission_to_student(
  p_adm_id      bigint,
  p_schema      text,
  p_class       text,
  p_stuadmno    text,
  p_allocatedby text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $fn$
DECLARE
  v_schema text := lower(p_schema);
  v        public.admission%ROWTYPE;
  v_stu_id bigint;
  v_par_id bigint;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = v_schema) THEN
    RAISE EXCEPTION 'allocate_admission: schema % does not exist', v_schema;
  END IF;

  SELECT * INTO v FROM public.admission WHERE adm_id = p_adm_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Admission % not found', p_adm_id;
  END IF;
  IF v.stu_id IS NOT NULL THEN
    RAISE EXCEPTION 'Admission % already allocated to student %', p_adm_id, v.stu_id;
  END IF;

  -- Self-heal: make sure the target schema's students table has the admission
  -- columns. This covers institutions created BEFORE this feature AND any
  -- created AFTER it, so create_institution_schema never has to be touched.
  -- ADD COLUMN IF NOT EXISTS is a fast metadata-only change (no-op if present).
  EXECUTE format('ALTER TABLE %I.students ADD COLUMN IF NOT EXISTS aadharno      varchar(20)', v_schema);
  EXECUTE format('ALTER TABLE %I.students ADD COLUMN IF NOT EXISTS community     varchar(30)', v_schema);
  EXECUTE format('ALTER TABLE %I.students ADD COLUMN IF NOT EXISTS caste         varchar(30)', v_schema);
  EXECUTE format('ALTER TABLE %I.students ADD COLUMN IF NOT EXISTS religion      varchar(30)', v_schema);
  EXECUTE format('ALTER TABLE %I.students ADD COLUMN IF NOT EXISTS nationality   varchar(30)', v_schema);
  EXECUTE format('ALTER TABLE %I.students ADD COLUMN IF NOT EXISTS transportmode varchar(10)', v_schema);
  EXECUTE format('ALTER TABLE %I.students ADD COLUMN IF NOT EXISTS hostel        char(1)', v_schema);

  -- 1) students (stu_id auto-assigned by the schema's set_stu_id trigger)
  EXECUTE format(
    'INSERT INTO %I.students '
    '(ins_id, inscode, yr_id, yrlabel, stuadmno, stuadmdate, stuname, stugender, studob, '
    ' stumobile, stuemail, stuaddress, stucity, stustate, stucountry, stupin, stubloodgrp, stuphoto, '
    ' stuclass, courname, con_id, stucondesc, stuser_id, stuotpstatus, '
    ' approvedby, approveddate, activestatus, createdon, batch, admname, quoname, admittyear, aadharno, '
    ' community, caste, religion, nationality, transportmode, hostel) '
    'VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,'
    ' $19,$20,$21,$22,$5,0,$23,now(),1,now(),$24,$25,$26,$27,$28,$29,$30,$31,$32,$33,$34) RETURNING stu_id', v_schema)
  INTO v_stu_id
  USING v.ins_id, v.inscode, v.yr_id, v.yrlabel, p_stuadmno, COALESCE(v.admdate, CURRENT_DATE),
        v.stuname, v.stugender, v.studob, v.stumobile, v.stuemail, v.stuaddress, v.stucity,
        v.stustate, v.stucountry, v.stupin, v.stubloodgrp, v.stuphoto, p_class, v.courname,
        v.con_id, v.stucondesc, p_allocatedby, v.batch, v.admname, v.quoname, v.admittyear, v.aadharno,
        v.community, v.caste, v.religion, v.nationality, v.transportmode, v.hostel;

  -- 2) parents — reuse an existing parent matched by payinchargemob, else create.
  IF v.payinchargemob IS NOT NULL AND TRIM(v.payinchargemob) <> '' THEN
    EXECUTE format('SELECT par_id FROM %I.parents WHERE payinchargemob = $1 LIMIT 1', v_schema)
      INTO v_par_id USING v.payinchargemob;
    IF v_par_id IS NULL THEN
      EXECUTE format(
        'INSERT INTO %I.parents '
        '(ins_id, yr_id, yrlabel, partype, fathername, fathermobile, fatheroccupation, '
        ' mothername, mothermobile, motheroccupation, guardianname, guardianmobile, guardianoccupation, '
        ' payincharge, payinchargemob, parotpstatus, approveddate, activestatus) '
        'VALUES ($1,$2,$3,''P'',$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,0,now(),1) RETURNING par_id', v_schema)
      INTO v_par_id
      USING v.ins_id, v.yr_id, v.yrlabel, v.fathername, v.fathermobile, v.fatheroccupation,
            v.mothername, v.mothermobile, v.motheroccupation, v.guardianname, v.guardianmobile,
            v.guardianoccupation, COALESCE(NULLIF(TRIM(v.payincharge), ''), v.stuname), v.payinchargemob;
    END IF;

    -- 3) parentdetail link
    EXECUTE format(
      'INSERT INTO %I.parentdetail '
      '(yr_id, yrlabel, par_id, stu_id, ins_id, inscode, stuadmno, stuname, stuclass, activestatus) '
      'VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,1)', v_schema)
    USING v.yr_id, v.yrlabel, v_par_id, v_stu_id, v.ins_id, v.inscode, p_stuadmno, v.stuname, p_class;
  END IF;

  -- 4) stamp the admission row as allocated
  UPDATE public.admission
     SET stu_id = v_stu_id,
         allocatedclass = p_class,
         admstatus = 'ALLOCATED',
         allocatedby = p_allocatedby,
         allocateddate = now()
   WHERE adm_id = p_adm_id;

  RETURN json_build_object(
    'adm_id', p_adm_id, 'stu_id', v_stu_id, 'par_id', v_par_id,
    'stuadmno', p_stuadmno, 'class', p_class, 'status', 'ALLOCATED');
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.allocate_admission_to_student(bigint, text, text, text, text)
  TO anon, authenticated;

NOTIFY pgrst, 'reload config';
