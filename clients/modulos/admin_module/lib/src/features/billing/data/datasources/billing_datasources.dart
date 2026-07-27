import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/payment_record.dart';
import '../../domain/model/plan.dart';
import '../../domain/model/subscription.dart';
import '../../domain/parameters/billing_parameters.dart';

/// Datasources da feature `billing`: I/O gRPC e conversão protobuf →
/// domínio. Todos burros — sem `try/catch`, a exceção sobe crua para o
/// `mapError` do repositório correspondente.

/// Lista os planos comerciais.
final class ListPlansDatasource implements Datasource<List<Plan>, NoParams> {
  final proto.AdminServiceClient _client;

  const ListPlansDatasource({required this._client});

  @override
  Future<List<Plan>> call(NoParams parameters) async {
    final resp = await _client.listPlans(proto.ListPlansRequest());
    return resp.plans
        .map(
          (p) => Plan(
            id: p.id,
            name: p.name,
            description: p.description,
            price: p.price,
            maxInstances: p.maxInstances,
            maxDepartments: p.maxDepartments,
            active: p.active,
            createdAt: DateTime.fromMillisecondsSinceEpoch(p.createdAt.toInt()),
          ),
        )
        .toList();
  }
}

/// Cria um plano.
final class CreatePlanDatasource
    implements Datasource<Plan, CreatePlanParameters> {
  final proto.AdminServiceClient _client;

  const CreatePlanDatasource({required this._client});

  @override
  Future<Plan> call(CreatePlanParameters parameters) async {
    final resp = await _client.createPlan(
      proto.CreatePlanRequest(
        name: parameters.name,
        description: parameters.description,
        price: parameters.price,
        maxInstances: parameters.maxInstances,
        maxDepartments: parameters.maxDepartments,
      ),
    );
    final p = resp.plan;
    return Plan(
      id: p.id,
      name: p.name,
      description: p.description,
      price: p.price,
      maxInstances: p.maxInstances,
      maxDepartments: p.maxDepartments,
      active: p.active,
      createdAt: DateTime.fromMillisecondsSinceEpoch(p.createdAt.toInt()),
    );
  }
}

/// Atualiza um plano.
final class UpdatePlanDatasource
    implements Datasource<Unit, UpdatePlanParameters> {
  final proto.AdminServiceClient _client;

  const UpdatePlanDatasource({required this._client});

  @override
  Future<Unit> call(UpdatePlanParameters parameters) async {
    await _client.updatePlan(
      proto.UpdatePlanRequest(
        id: parameters.id,
        name: parameters.name,
        description: parameters.description,
        price: parameters.price,
        maxInstances: parameters.maxInstances,
        maxDepartments: parameters.maxDepartments,
        active: parameters.active,
      ),
    );
    return unit;
  }
}

/// Lista as assinaturas ativas.
final class ListSubscriptionsDatasource
    implements Datasource<List<Subscription>, NoParams> {
  final proto.AdminServiceClient _client;

  const ListSubscriptionsDatasource({required this._client});

  @override
  Future<List<Subscription>> call(NoParams parameters) async {
    final resp = await _client.listSubscriptions(
      proto.ListSubscriptionsRequest(),
    );
    return resp.subscriptions
        .map(
          (s) => Subscription(
            id: s.id,
            tenantId: s.tenantId,
            planId: s.planId,
            status: s.status,
            currentPeriodStart: DateTime.fromMillisecondsSinceEpoch(
              s.currentPeriodStart.toInt(),
            ),
            currentPeriodEnd: DateTime.fromMillisecondsSinceEpoch(
              s.currentPeriodEnd.toInt(),
            ),
            paymentGateway: s.paymentGateway,
            externalCustomerId: s.externalCustomerId,
            externalSubscriptionId: s.externalSubscriptionId,
            updatedAt: DateTime.fromMillisecondsSinceEpoch(s.updatedAt.toInt()),
          ),
        )
        .toList();
  }
}

/// Registra um pagamento recebido.
final class RegisterPaymentDatasource
    implements Datasource<PaymentRecord, RegisterPaymentParameters> {
  final proto.AdminServiceClient _client;

  const RegisterPaymentDatasource({required this._client});

  @override
  Future<PaymentRecord> call(RegisterPaymentParameters parameters) async {
    final resp = await _client.registerPayment(
      proto.RegisterPaymentRequest(
        tenantId: parameters.tenantId,
        amount: parameters.amount,
        paymentMethod: parameters.paymentMethod,
        paymentDate: parameters.paymentDate,
        periodStart: parameters.periodStart,
        periodEnd: parameters.periodEnd,
        notes: parameters.notes,
      ),
    );
    final p = resp.payment;
    return PaymentRecord(
      id: p.id,
      tenantId: p.tenantId,
      amount: p.amount,
      paymentDate: p.paymentDate,
      paymentMethod: p.paymentMethod,
      periodStart: p.periodStart,
      periodEnd: p.periodEnd,
      notes: p.notes,
      recordedById: p.recordedById,
      createdAt: DateTime.fromMillisecondsSinceEpoch(p.createdAt.toInt()),
    );
  }
}

/// Lista pagamentos (todos ou de um tenant).
final class ListPaymentsDatasource
    implements Datasource<List<PaymentRecord>, ListPaymentsParameters> {
  final proto.AdminServiceClient _client;

  const ListPaymentsDatasource({required this._client});

  @override
  Future<List<PaymentRecord>> call(ListPaymentsParameters parameters) async {
    final resp = await _client.listPayments(
      proto.ListPaymentsRequest(tenantId: parameters.tenantId ?? ''),
    );
    return resp.payments
        .map(
          (p) => PaymentRecord(
            id: p.id,
            tenantId: p.tenantId,
            amount: p.amount,
            paymentDate: p.paymentDate,
            paymentMethod: p.paymentMethod,
            periodStart: p.periodStart,
            periodEnd: p.periodEnd,
            notes: p.notes,
            recordedById: p.recordedById,
            createdAt: DateTime.fromMillisecondsSinceEpoch(p.createdAt.toInt()),
          ),
        )
        .toList();
  }
}
