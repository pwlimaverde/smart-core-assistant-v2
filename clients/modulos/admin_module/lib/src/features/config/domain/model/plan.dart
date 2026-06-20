import 'package:meta/meta.dart';

@immutable
class Plan {
  final int id;
  final String name;
  final String description;
  final String price;
  final int maxInstances;
  final int maxDepartments;
  final bool active;
  final DateTime createdAt;

  const Plan({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.maxInstances,
    required this.maxDepartments,
    required this.active,
    required this.createdAt,
  });
}
