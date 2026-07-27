import 'package:meta/meta.dart';

@immutable
class Tenant {
  final String id;
  final String name;
  final String slug;
  final String apiKey;
  final int ownerId;
  final String email;
  final String phone;
  final bool active;
  final bool setupCompleted;
  final int onboardingStep;
  final String accessCode;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Tenant({
    required this.id,
    required this.name,
    required this.slug,
    required this.apiKey,
    required this.ownerId,
    required this.email,
    required this.phone,
    required this.active,
    required this.setupCompleted,
    required this.onboardingStep,
    required this.accessCode,
    required this.createdAt,
    required this.updatedAt,
  });
}
