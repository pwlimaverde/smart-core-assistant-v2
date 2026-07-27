import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/tenant.dart';
import '../../domain/parameters/tenants_parameters.dart';

/// Datasources da feature `tenants`: I/O gRPC e conversão protobuf →
/// domínio. Todos burros — sem `try/catch`, a exceção sobe crua para o
/// `mapError` do repositório correspondente.

/// Lista todos os tenants.
final class ListTenantsDatasource
    implements Datasource<List<Tenant>, NoParams> {
  final proto.AdminServiceClient _client;

  const ListTenantsDatasource({required this._client});

  @override
  Future<List<Tenant>> call(NoParams parameters) async {
    final resp = await _client.listTenants(proto.ListTenantsRequest());
    return resp.tenants
        .map(
          (t) => Tenant(
            id: t.id,
            name: t.name,
            slug: t.slug,
            apiKey: t.apiKey,
            ownerId: t.ownerId,
            email: t.email,
            phone: t.phone,
            active: t.active,
            setupCompleted: t.setupCompleted,
            onboardingStep: t.onboardingStep,
            accessCode: t.accessCode,
            createdAt: DateTime.fromMillisecondsSinceEpoch(t.createdAt.toInt()),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(t.updatedAt.toInt()),
          ),
        )
        .toList();
  }
}

/// Carrega um tenant pelo id.
final class GetTenantDatasource
    implements Datasource<Tenant, GetTenantParameters> {
  final proto.AdminServiceClient _client;

  const GetTenantDatasource({required this._client});

  @override
  Future<Tenant> call(GetTenantParameters parameters) async {
    final resp = await _client.getTenant(
      proto.GetTenantRequest(id: parameters.id),
    );
    final t = resp.tenant;
    return Tenant(
      id: t.id,
      name: t.name,
      slug: t.slug,
      apiKey: t.apiKey,
      ownerId: t.ownerId,
      email: t.email,
      phone: t.phone,
      active: t.active,
      setupCompleted: t.setupCompleted,
      onboardingStep: t.onboardingStep,
      accessCode: t.accessCode,
      createdAt: DateTime.fromMillisecondsSinceEpoch(t.createdAt.toInt()),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(t.updatedAt.toInt()),
    );
  }
}

/// Cria um tenant.
final class CreateTenantDatasource
    implements Datasource<Tenant, CreateTenantParameters> {
  final proto.AdminServiceClient _client;

  const CreateTenantDatasource({required this._client});

  @override
  Future<Tenant> call(CreateTenantParameters parameters) async {
    final resp = await _client.createTenant(
      proto.CreateTenantRequest(
        name: parameters.name,
        slug: parameters.slug,
        ownerId: parameters.ownerId,
        email: parameters.email,
        phone: parameters.phone,
      ),
    );
    final t = resp.tenant;
    return Tenant(
      id: t.id,
      name: t.name,
      slug: t.slug,
      apiKey: t.apiKey,
      ownerId: t.ownerId,
      email: t.email,
      phone: t.phone,
      active: t.active,
      setupCompleted: t.setupCompleted,
      onboardingStep: t.onboardingStep,
      accessCode: t.accessCode,
      createdAt: DateTime.fromMillisecondsSinceEpoch(t.createdAt.toInt()),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(t.updatedAt.toInt()),
    );
  }
}

/// Atualiza os dados de um tenant.
final class UpdateTenantDatasource
    implements Datasource<Unit, UpdateTenantParameters> {
  final proto.AdminServiceClient _client;

  const UpdateTenantDatasource({required this._client});

  @override
  Future<Unit> call(UpdateTenantParameters parameters) async {
    await _client.updateTenant(
      proto.UpdateTenantRequest(
        id: parameters.id,
        name: parameters.name,
        slug: parameters.slug,
        ownerId: parameters.ownerId,
        email: parameters.email,
        phone: parameters.phone,
      ),
    );
    return unit;
  }
}

/// Ativa ou desativa um tenant.
final class SetTenantActiveDatasource
    implements Datasource<Unit, SetTenantActiveParameters> {
  final proto.AdminServiceClient _client;

  const SetTenantActiveDatasource({required this._client});

  @override
  Future<Unit> call(SetTenantActiveParameters parameters) async {
    await _client.setTenantActive(
      proto.SetTenantActiveRequest(
        id: parameters.id,
        active: parameters.active,
      ),
    );
    return unit;
  }
}

/// Gera um novo código de acesso (API key) do tenant.
final class GenerateAccessCodeDatasource
    implements Datasource<String, GenerateAccessCodeParameters> {
  final proto.AdminServiceClient _client;

  const GenerateAccessCodeDatasource({required this._client});

  @override
  Future<String> call(GenerateAccessCodeParameters parameters) async {
    final resp = await _client.generateAccessCode(
      proto.GenerateAccessCodeRequest(id: parameters.id),
    );
    return resp.accessCode;
  }
}

/// Exporta a lista de tenants em CSV (bytes).
final class ExportTenantsCsvDatasource
    implements Datasource<List<int>, NoParams> {
  final proto.AdminServiceClient _client;

  const ExportTenantsCsvDatasource({required this._client});

  @override
  Future<List<int>> call(NoParams parameters) async {
    final stream = _client.exportTenantsCsv(proto.ExportTenantsCsvRequest());
    final List<int> bytes = [];
    await for (final resp in stream) {
      bytes.addAll(resp.chunk);
    }
    return bytes;
  }
}
