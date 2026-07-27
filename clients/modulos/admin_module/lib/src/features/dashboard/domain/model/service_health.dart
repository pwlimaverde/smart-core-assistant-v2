final class ServiceHealth {
  final String serviceName;
  final String status; // "healthy", "unhealthy", "degraded"
  final String message;
  final int responseTimeMs;

  const ServiceHealth({
    required this.serviceName,
    required this.status,
    required this.message,
    required this.responseTimeMs,
  });
}
