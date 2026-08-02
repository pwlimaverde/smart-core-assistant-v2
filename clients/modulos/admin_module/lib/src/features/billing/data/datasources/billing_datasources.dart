import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/payment_record.dart';
import '../../domain/model/plan.dart';
import '../../domain/model/subscription.dart';
import '../../domain/model/voucher.dart';
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
            maxFluxos: p.maxFluxos,
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
        maxFluxos: parameters.maxFluxos,
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
      maxFluxos: p.maxFluxos,
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
        maxFluxos: parameters.maxFluxos,
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

// --- Vouchers de ativação ---

/// Converte epoch-ms em `DateTime`; 0 significa "ausente" no contrato do proto
/// (proto3 não distingue campo não preenchido de zero em escalares).
DateTime? _dataOpcional(int epochMs) =>
    epochMs == 0 ? null : DateTime.fromMillisecondsSinceEpoch(epochMs);

Voucher _voucherDoProto(proto.Voucher v) => Voucher(
  id: v.id,
  codigo: v.codigo,
  descricao: v.descricao,
  planId: v.planId,
  planName: v.planName,
  duracaoDias: v.duracaoDias,
  maxResgates: v.maxResgates,
  resgatesUsados: v.resgatesUsados,
  validoDe: DateTime.fromMillisecondsSinceEpoch(v.validoDe.toInt()),
  validoAte: _dataOpcional(v.validoAte.toInt()),
  revogadoEm: _dataOpcional(v.revogadoEm.toInt()),
  motivoRevogacao: v.motivoRevogacao,
  createdAt: DateTime.fromMillisecondsSinceEpoch(v.createdAt.toInt()),
);

/// Lista os vouchers.
final class ListVouchersDatasource
    implements Datasource<List<Voucher>, NoParams> {
  final proto.AdminServiceClient _client;

  const ListVouchersDatasource({required this._client});

  @override
  Future<List<Voucher>> call(NoParams parameters) async {
    final resp = await _client.listVouchers(proto.ListVouchersRequest());
    return resp.vouchers.map(_voucherDoProto).toList();
  }
}

/// Cria um voucher.
final class CreateVoucherDatasource
    implements Datasource<Voucher, CreateVoucherParameters> {
  final proto.AdminServiceClient _client;

  const CreateVoucherDatasource({required this._client});

  @override
  Future<Voucher> call(CreateVoucherParameters parameters) async {
    final resp = await _client.createVoucher(
      proto.CreateVoucherRequest(
        codigo: parameters.codigo,
        descricao: parameters.descricao,
        planId: parameters.planId,
        duracaoDias: parameters.duracaoDias,
        maxResgates: parameters.maxResgates,
        validoAte: parameters.validoAte,
      ),
    );
    return _voucherDoProto(resp.voucher);
  }
}

/// Revoga um voucher. `false` = já estava revogado (não é erro).
final class RevokeVoucherDatasource
    implements Datasource<bool, RevokeVoucherParameters> {
  final proto.AdminServiceClient _client;

  const RevokeVoucherDatasource({required this._client});

  @override
  Future<bool> call(RevokeVoucherParameters parameters) async {
    final resp = await _client.revokeVoucher(
      proto.RevokeVoucherRequest(
        voucherId: parameters.voucherId,
        motivo: parameters.motivo,
      ),
    );
    return resp.revogado;
  }
}

/// Histórico de resgates de um voucher.
final class ListVoucherRedemptionsDatasource
    implements
        Datasource<List<VoucherRedemption>, VoucherRedemptionsParameters> {
  final proto.AdminServiceClient _client;

  const ListVoucherRedemptionsDatasource({required this._client});

  @override
  Future<List<VoucherRedemption>> call(
    VoucherRedemptionsParameters parameters,
  ) async {
    final resp = await _client.listVoucherRedemptions(
      proto.ListVoucherRedemptionsRequest(voucherId: parameters.voucherId),
    );
    return resp.resgates
        .map(
          (r) => VoucherRedemption(
            id: r.id,
            voucherId: r.voucherId,
            tenantId: r.tenantId,
            planId: r.planId,
            periodoInicio: DateTime.fromMillisecondsSinceEpoch(
              r.periodoInicio.toInt(),
            ),
            periodoFim: DateTime.fromMillisecondsSinceEpoch(
              r.periodoFim.toInt(),
            ),
            ip: r.ip,
            redeemedAt: DateTime.fromMillisecondsSinceEpoch(
              r.redeemedAt.toInt(),
            ),
          ),
        )
        .toList();
  }
}
