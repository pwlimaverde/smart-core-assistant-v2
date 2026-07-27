import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/tenants_errors.dart';
import '../model/tenant.dart';
import '../parameters/tenants_parameters.dart';

/// Casos de uso da feature `tenants`.
///
/// Os `process` são passthrough: a regra de negócio destas operações vive no
/// servidor (é o painel do superusuário). O que a base agrega aqui é o
/// `onUnexpected` — nenhuma exceção do processamento escapa para o controller.

void _logBug(String operacao, Object exception, StackTrace stackTrace) =>
    developer.log(
      'process de \$operacao quebrou',
      name: 'admin_module.tenants',
      error: exception,
      stackTrace: stackTrace,
    );

/// Lista todos os tenants.
final class ListTenantsUsecase
    extends
        UsecaseBaseCallData<
          List<Tenant>,
          List<Tenant>,
          NoParams,
          TenantsError
        > {
  const ListTenantsUsecase({required super.repository});

  @override
  ProcessData<List<Tenant>, List<Tenant>, NoParams, TenantsError> get process =>
      _process;

  @override
  TenantsError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('listTenants', exception, stackTrace);
    return const TenantsInesperado();
  }

  static ReturnSuccessOrError<List<Tenant>, TenantsError> _process(
    List<Tenant> data,
    NoParams parameters,
  ) => Success(data);
}

/// Carrega um tenant pelo id.
final class GetTenantUsecase
    extends
        UsecaseBaseCallData<Tenant, Tenant, GetTenantParameters, TenantsError> {
  const GetTenantUsecase({required super.repository});

  @override
  ProcessData<Tenant, Tenant, GetTenantParameters, TenantsError> get process =>
      _process;

  @override
  TenantsError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('getTenant', exception, stackTrace);
    return const TenantsInesperado();
  }

  static ReturnSuccessOrError<Tenant, TenantsError> _process(
    Tenant data,
    GetTenantParameters parameters,
  ) => Success(data);
}

/// Cria um tenant.
final class CreateTenantUsecase
    extends
        UsecaseBaseCallData<
          Tenant,
          Tenant,
          CreateTenantParameters,
          TenantsError
        > {
  const CreateTenantUsecase({required super.repository});

  @override
  ProcessData<Tenant, Tenant, CreateTenantParameters, TenantsError>
  get process => _process;

  @override
  TenantsError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('createTenant', exception, stackTrace);
    return const TenantsInesperado();
  }

  static ReturnSuccessOrError<Tenant, TenantsError> _process(
    Tenant data,
    CreateTenantParameters parameters,
  ) => Success(data);
}

/// Atualiza os dados de um tenant.
final class UpdateTenantUsecase
    extends
        UsecaseBaseCallData<Unit, Unit, UpdateTenantParameters, TenantsError> {
  const UpdateTenantUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, UpdateTenantParameters, TenantsError> get process =>
      _process;

  @override
  TenantsError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('updateTenant', exception, stackTrace);
    return const TenantsInesperado();
  }

  static ReturnSuccessOrError<Unit, TenantsError> _process(
    Unit data,
    UpdateTenantParameters parameters,
  ) => Success(data);
}

/// Ativa ou desativa um tenant.
final class SetTenantActiveUsecase
    extends
        UsecaseBaseCallData<
          Unit,
          Unit,
          SetTenantActiveParameters,
          TenantsError
        > {
  const SetTenantActiveUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, SetTenantActiveParameters, TenantsError>
  get process => _process;

  @override
  TenantsError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('setTenantActive', exception, stackTrace);
    return const TenantsInesperado();
  }

  static ReturnSuccessOrError<Unit, TenantsError> _process(
    Unit data,
    SetTenantActiveParameters parameters,
  ) => Success(data);
}

/// Gera um novo código de acesso (API key) do tenant.
final class GenerateAccessCodeUsecase
    extends
        UsecaseBaseCallData<
          String,
          String,
          GenerateAccessCodeParameters,
          TenantsError
        > {
  const GenerateAccessCodeUsecase({required super.repository});

  @override
  ProcessData<String, String, GenerateAccessCodeParameters, TenantsError>
  get process => _process;

  @override
  TenantsError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('generateAccessCode', exception, stackTrace);
    return const TenantsInesperado();
  }

  static ReturnSuccessOrError<String, TenantsError> _process(
    String data,
    GenerateAccessCodeParameters parameters,
  ) => Success(data);
}

/// Exporta a lista de tenants em CSV (bytes).
final class ExportTenantsCsvUsecase
    extends UsecaseBaseCallData<List<int>, List<int>, NoParams, TenantsError> {
  const ExportTenantsCsvUsecase({required super.repository});

  @override
  ProcessData<List<int>, List<int>, NoParams, TenantsError> get process =>
      _process;

  @override
  TenantsError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('exportTenantsCsv', exception, stackTrace);
    return const TenantsInesperado();
  }

  static ReturnSuccessOrError<List<int>, TenantsError> _process(
    List<int> data,
    NoParams parameters,
  ) => Success(data);
}
