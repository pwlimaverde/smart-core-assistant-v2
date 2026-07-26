import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/convites_errors.dart';
import '../model/accepted_tenant_user.dart';
import '../model/tenant_invite.dart';
import '../parameters/convites_parameters.dart';

void _logBug(String operacao, Object exception, StackTrace stackTrace) =>
    developer.log(
      'process de $operacao quebrou',
      name: 'tenant_module.convites',
      error: exception,
      stackTrace: stackTrace,
    );

final class CreateInviteUsecase
    extends
        UsecaseBaseCallData<
          TenantInviteCreated,
          TenantInviteCreated,
          CreateInviteParameters,
          ConvitesError
        > {
  const CreateInviteUsecase({required super.repository});

  @override
  ProcessData<
    TenantInviteCreated,
    TenantInviteCreated,
    CreateInviteParameters,
    ConvitesError
  >
  get process => _process;

  @override
  ConvitesError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('createInvite', exception, stackTrace);
    return const ConvitesInesperado();
  }

  static ReturnSuccessOrError<TenantInviteCreated, ConvitesError> _process(
    TenantInviteCreated data,
    CreateInviteParameters parameters,
  ) => Success(data);
}

final class ListInvitesUsecase
    extends
        UsecaseBaseCallData<
          List<TenantInvite>,
          List<TenantInvite>,
          NoParams,
          ConvitesError
        > {
  const ListInvitesUsecase({required super.repository});

  @override
  ProcessData<List<TenantInvite>, List<TenantInvite>, NoParams, ConvitesError>
  get process => _process;

  @override
  ConvitesError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('listInvites', exception, stackTrace);
    return const ConvitesInesperado();
  }

  /// Regra da feature: convites pendentes primeiro, e dentro de cada grupo os
  /// mais recentes no topo.
  ///
  /// A tela de convites existe para agir sobre o que está pendente; deixar um
  /// convite revogado de três meses atrás acima de um pendente de hoje só porque
  /// o servidor ordenou por id enterraria a informação útil.
  static ReturnSuccessOrError<List<TenantInvite>, ConvitesError> _process(
    List<TenantInvite> data,
    NoParams parameters,
  ) {
    bool pendente(TenantInvite i) => !i.used && !i.revoked;
    final ordenados = [...data]
      ..sort((a, b) {
        if (pendente(a) != pendente(b)) return pendente(a) ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });
    return Success(List.unmodifiable(ordenados));
  }
}

final class RevokeInviteUsecase
    extends
        UsecaseBaseCallData<Unit, Unit, RevokeInviteParameters, ConvitesError> {
  const RevokeInviteUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, RevokeInviteParameters, ConvitesError> get process =>
      _process;

  @override
  ConvitesError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('revokeInvite', exception, stackTrace);
    return const ConvitesInesperado();
  }

  static ReturnSuccessOrError<Unit, ConvitesError> _process(
    Unit data,
    RevokeInviteParameters parameters,
  ) => const Success(unit);
}

final class AcceptInviteUsecase
    extends
        UsecaseBaseCallData<
          AcceptedTenantUser,
          AcceptedTenantUser,
          AcceptInviteParameters,
          AcceptInviteError
        > {
  const AcceptInviteUsecase({required super.repository});

  @override
  ProcessData<
    AcceptedTenantUser,
    AcceptedTenantUser,
    AcceptInviteParameters,
    AcceptInviteError
  >
  get process => _process;

  @override
  AcceptInviteError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('acceptInvite', exception, stackTrace);
    return const AcceptInesperado();
  }

  static ReturnSuccessOrError<AcceptedTenantUser, AcceptInviteError> _process(
    AcceptedTenantUser data,
    AcceptInviteParameters parameters,
  ) => Success(data);
}
