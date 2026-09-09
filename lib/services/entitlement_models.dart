/// Monotonic revisions stay exactly representable by JavaScript backends.
const int maximumEntitlementRevision = 9007199254740991;

/// Monthly-product responses are bounded to tolerate renewal timing safely.
const Duration maximumVerifiedVipHorizon = Duration(days: 62);

/// Server-authored account state attached to verification and refresh responses.
class AuthoritativeEntitlementSnapshot {
  const AuthoritativeEntitlementSnapshot({
    required this.revision,
    required this.generatedAt,
    required this.vipUntil,
  });

  final int revision;
  final DateTime generatedAt;
  final DateTime? vipUntil;
}

enum EntitlementReconciliationOutcome { applied, unchanged, stale }
