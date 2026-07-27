final class AuditLogEntry {
  final int id;
  final String eventType;
  final String actor;
  final String tenantId;
  final String description;
  final String ipAddress;
  final String userAgent;
  final DateTime createdAt;

  const AuditLogEntry({
    required this.id,
    required this.eventType,
    required this.actor,
    required this.tenantId,
    required this.description,
    required this.ipAddress,
    required this.userAgent,
    required this.createdAt,
  });
}
