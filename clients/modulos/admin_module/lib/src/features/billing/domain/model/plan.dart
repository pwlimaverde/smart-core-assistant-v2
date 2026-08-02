import 'package:meta/meta.dart';

@immutable
class Plan {
  final int id;
  final String name;
  final String description;
  final String price;
  final int maxInstances;
  final int maxDepartments;

  /// Teto de fluxos de atendimento do plano. Nasceu na migration dos vouchers
  /// e precisa trafegar em TODA edição: o `UpdatePlan` grava o valor recebido,
  /// então um cliente que não o envia zera o limite do plano sem avisar.
  final int maxFluxos;
  final bool active;
  final DateTime createdAt;

  const Plan({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.maxInstances,
    required this.maxDepartments,
    required this.maxFluxos,
    required this.active,
    required this.createdAt,
  });
}
