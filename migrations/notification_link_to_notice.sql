-- Link each notification row back to its parent notice so expired
-- notices can cascade-delete their child notifications.
--
-- Before: when a notice was deleted (after noticetodate passed) the
-- corresponding rows in `notification` were orphaned forever — there
-- was no way to tell which inbox entries came from which notice. They
-- piled up indefinitely and admins had to clean them by hand.
--
-- After: every notification carries notice_id; the notices_screen
-- sweep now also deletes notifications whose notice_id is in the
-- expired set.
--
-- Idempotent — safe to re-run across all per-institution schemas.

DO $mig$
DECLARE rec RECORD;
BEGIN
  FOR rec IN
    SELECT table_schema AS s
    FROM information_schema.tables
    WHERE table_name = 'notification'
      AND table_schema NOT IN ('public','pg_catalog','information_schema',
                               'storage','auth','realtime',
                               'supabase_functions','extensions')
  LOOP
    EXECUTE format(
      'ALTER TABLE %I.notification ADD COLUMN IF NOT EXISTS notice_id bigint',
      rec.s);
    -- Index by notice_id so the cascade DELETE is cheap even with
    -- thousands of student notifications per notice.
    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS idx_notification_notice_id ON %I.notification(notice_id)',
      rec.s);
    RAISE NOTICE 'notification.notice_id installed in schema: %', rec.s;
  END LOOP;
END;
$mig$;
