/// Turn a raw exception into a short, accountant-readable sentence.
///
/// Most callers do `catch (e) { showSnackBar(Text('Error: $e')); }` which
/// dumps `PostgrestException(message: new row violates row-level security
/// policy for table "payment", code: 42501, ...)` into the UI. Replace
/// those call sites with `friendlyError(e)` so the user sees an actionable
/// message instead.
String friendlyError(Object e) {
  final s = e.toString();
  final lower = s.toLowerCase();

  // Network reachability
  if (lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('connection refused') ||
      lower.contains('network is unreachable')) {
    return 'Cannot reach the server. Check your internet connection and try again.';
  }
  if (lower.contains('timeoutexception') || lower.contains('timed out')) {
    return 'The server took too long to respond. Try again in a moment.';
  }

  // Supabase PostgREST
  if (lower.contains('pgrst106') || lower.contains('invalid schema')) {
    return 'This institution\'s data isn\'t exposed yet. Ask the super admin to finish schema setup.';
  }
  if (lower.contains('42501') ||
      lower.contains('row-level security') ||
      lower.contains('permission denied')) {
    return 'You don\'t have permission to perform this action.';
  }
  if (lower.contains('duplicate key') || lower.contains('23505')) {
    return 'That record already exists. Refresh and try again.';
  }
  if (lower.contains('foreign key') || lower.contains('23503')) {
    return 'This record is linked to other data and cannot be changed right now.';
  }
  if (lower.contains('already paid') || lower.contains('p0001')) {
    // Raised by process_grouped_payment's balance guard
    final match = RegExp(r"Demand \d+ is already paid").firstMatch(s);
    if (match != null) {
      return 'One of the selected fees has already been collected by another user. Please refresh.';
    }
  }
  if (lower.contains('no schema found')) {
    return 'Institution schema is missing. Contact the super admin.';
  }

  // Storage / file issues
  if (lower.contains('bucket not found')) {
    return 'Storage bucket is missing on the server. Contact the super admin.';
  }
  if (lower.contains('payload too large') || lower.contains('413')) {
    return 'File is too large to upload. Please use a smaller file.';
  }

  // Razorpay edge function / gateway
  if (lower.contains('order_id') && lower.contains('not found')) {
    return 'Payment order not found. Start a fresh payment.';
  }

  // Fall back to a generic sentence. Don\'t dump the raw exception — it\'s
  // scary for a non-technical cashier. If they need the detail, it\'s in
  // the log.
  return 'Something went wrong. Please try again. If it keeps happening, contact support.';
}
