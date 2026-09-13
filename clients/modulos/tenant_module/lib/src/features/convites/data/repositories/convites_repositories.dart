import 'dart:developer' as developer;

import 'package:api_client/api_client.dart'
    show GrpcFailureKind, classificarFalhaGrpc;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/convites_errors.dart';
import '../../domain/model/accepted_tenant_user.dart';
import '../../domain/model/tenant_invite.dart';
import '../../domain/parameters/convites_parameters.dart';

/// Tradução compartilhada pelas três operações autenticadas de convite.
///
/// O log não inclui o e-mail convidado: é dado pessoal, e o diagnóstico só
/// precisa da natureza da falha.
ConvitesError _mapConvites(
  String operacao,
  Object exception,
  StackTrace stackTrace,
) {
  final kind = classificarFalhaGrpc(exception);
  developer.log(
    '$operacao falhou: $kind',
    name: 'tenant_module.convites',
    error: exception,
    stackTrace: stackTrace,
  );
  return switch (kind) {
    // Separados de propósito: sessão expirada não é falta de
    // permissão, e juntar as duas manda a pessoa caçar um acesso
    // que ela já tem.
    GrpcFailureKind.unauthenticated => const ConvitesSessaoExpirada(),
    GrpcFailureKind.permissionDenied => const ConvitesAcessoNegado(),
    GrpcFailureKind.notFound => const ConviteNaoEncontrado(),
    GrpcFailureKind.alreadyExists => const EmailJaConvidado(),
    GrpcFailureKind.invalidArgument ||
    GrpcFailureKind.failedPrecondition => const ConvitesDadosInvalidos(),
    GrpcFailureKind.unavailable ||
    GrpcFailureKind.rateLimited => const ConvitesIndisponivel(),
    GrpcFailureKind.unknown => const ConvitesInesperado(),
  };
}

final class CreateInviteRepository
    extends
        RepositoryBase<
          TenantInviteCreated,
          CreateInviteParameters,
          ConvitesError
        > {
  const CreateInviteRepository({required super.datasource});

  @override
  ConvitesError mapError(
    Object exception,
    StackTrace stackTrace,
    CreateInviteParameters parameters,
  ) => _mapConvites('createInvite', exception, stackTrace);
}

final class ListInvitesRepository
    extends RepositoryBase<List<TenantInvite>, NoParams, ConvitesError> {
  const ListInvitesRepository({required super.datasource});

  @override
  ConvitesError mapError(
    Object exception,
    StackTrace stackTrace,
    NoParams parameters,
  ) => _mapConvites('listInvites', exception, stackTrace);
}

final class RevokeInviteRepository
    extends RepositoryBase<Unit, RevokeInviteParameters, ConvitesError> {
  const RevokeInviteRepository({required super.datasource});

  @override
  ConvitesError mapError(
    Object exception,
    StackTrace stackTrace,
    RevokeInviteParameters parameters,
  ) => _mapConvites('revokeInvite', exception, stackTrace);
}

/// Fronteira do aceite — a única rota pública do módulo.
///
/// `notFound`, `failedPrecondition` e `invalidArgument` sobre o **token** caem
/// todos em [ConviteInvalidoOuExpirado]: distinguir diria a quem tem o link se
/// aquele convite existiu. Só a recusa do **cadastro** (e-mail/senha) é separada.
final class AcceptInviteRepository
    extends
        RepositoryBase<
          AcceptedTenantUser,
          AcceptInviteParameters,
          AcceptInviteError
        > {
  const AcceptInviteRepository({required super.datasource});

  @override
  AcceptInviteError mapError(
    Object exception,
    StackTrace stackTrace,
    AcceptInviteParameters parameters,
  ) {
    final kind = classificarFalhaGrpc(exception);
    // Nem o token, nem o e-mail, nem a senha entram no log.
    developer.log(
      'acceptInvite falhou: $kind',
      name: 'tenant_module.convites',
      error: exception,
      stackTrace: stackTrace,
    );
    return switch (kind) {
      GrpcFailureKind.notFound ||
      GrpcFailureKind.failedPrecondition ||
      GrpcFailureKind.permissionDenied ||
      GrpcFailureKind.unauthenticated => const ConviteInvalidoOuExpirado(),
      GrpcFailureKind.alreadyExists => const UsuarioJaExiste(),
      GrpcFailureKind.invalidArgument => const AcceptDadosInvalidos(),
      GrpcFailureKind.unavailable ||
      GrpcFailureKind.rateLimited => const AcceptIndisponivel(),
      GrpcFailureKind.unknown => const AcceptInesperado(),
    };
  }
}

/// Reenviar tem dois desfechos que as outras operações não têm — o limite por
/// hora e o convite que já terminou —, e cada um merece a própria frase.
final class ReenviarConviteRepository
    extends RepositoryBase<DateTime, ReenviarConviteParameters, ConvitesError> {
  const ReenviarConviteRepository({required super.datasource});

  @override
  ConvitesError mapError(
    Object exception,
    StackTrace stackTrace,
    ReenviarConviteParameters parameters,
  ) {
    // `_mapConvites` registra no log; o resultado dele vale para o resto.
    final padrao = _mapConvites('reenviarConvite', exception, stackTrace);
    return switch (classificarFalhaGrpc(exception)) {
      GrpcFailureKind.rateLimited => const ConviteReenviadoRecentemente(),
      GrpcFailureKind.failedPrecondition => const ConviteNaoReenviavel(),
      _ => padrao,
    };
  }
}
