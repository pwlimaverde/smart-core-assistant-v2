import 'package:flutter_test/flutter_test.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:tenant_module/src/features/config/domain/errors/config_errors.dart';
import 'package:tenant_module/src/features/config/domain/model/tenant_config.dart';
import 'package:tenant_module/src/features/config/domain/parameters/config_parameters.dart';
import 'package:tenant_module/src/features/config/domain/usecases/config_usecases.dart';
import 'package:tenant_module/src/features/convites/domain/errors/convites_errors.dart';
import 'package:tenant_module/src/features/convites/domain/model/accepted_tenant_user.dart';
import 'package:tenant_module/src/features/convites/domain/model/tenant_invite.dart';
import 'package:tenant_module/src/features/convites/domain/parameters/convites_parameters.dart';
import 'package:tenant_module/src/features/convites/domain/usecases/convites_usecases.dart';
import 'package:tenant_module/src/features/usuarios/domain/errors/usuarios_errors.dart';
import 'package:tenant_module/src/features/usuarios/domain/model/tenant_user.dart';
import 'package:tenant_module/src/features/usuarios/domain/parameters/usuarios_parameters.dart';
import 'package:tenant_module/src/features/usuarios/domain/usecases/usuarios_usecases.dart';

/// Repositório que quebra o contrato: lança em vez de devolver `Failure`.
///
/// A base do usecase converte isso via `onUnexpected` — é a garantia de que
/// nenhuma exceção chega ao controller, e só uma implementação manual fora do
/// contrato consegue exercitá-la.
final class _RepoQueLanca<TData, TParams extends Parameters, TError>
    implements Repository<TData, TParams, TError> {
  @override
  Future<ReturnSuccessOrError<TData, TError>> call(TParams parameters) async {
    throw StateError('repositorio fora do contrato');
  }
}

const _config = TenantConfig(
  dadosEmpresa: '',
  personaBot: '',
  botAgentName: '',
  msgFallback: '',
  msgSemInfo: '',
  msgTransferencia: '',
  llmClass: '',
  model: '',
  llmTemperature: '',
  transcriptionProvider: '',
  transcriptionModel: '',
  visionProvider: '',
  visionModel: '',
  embeddingsClass: '',
  embeddingsModel: '',
  chunkSize: 0,
  chunkOverlap: 0,
  similarityThreshold: '',
  vectorDistanceThreshold: '',
  apiKeys: {},
);

void main() {
  group('convites', () {
    test('createInvite converte bug do repositório', () async {
      final r =
          await CreateInviteUsecase(
            repository:
                _RepoQueLanca<
                  TenantInviteCreated,
                  CreateInviteParameters,
                  ConvitesError
                >(),
          )(
            const CreateInviteParameters(
              email: 'a@b.com',
              name: 'n',
              role: 'atendente',
            ),
          );

      expect((r as Failure).error, isA<ConvitesInesperado>());
    });

    test('listInvites converte bug do repositório', () async {
      final r = await ListInvitesUsecase(
        repository:
            _RepoQueLanca<List<TenantInvite>, NoParams, ConvitesError>(),
      )(noParams);

      expect((r as Failure).error, isA<ConvitesInesperado>());
    });

    test('revokeInvite converte bug do repositório', () async {
      final r = await RevokeInviteUsecase(
        repository:
            _RepoQueLanca<Unit, RevokeInviteParameters, ConvitesError>(),
      )(const RevokeInviteParameters(inviteId: 'i1'));

      expect((r as Failure).error, isA<ConvitesInesperado>());
    });

    test('acceptInvite converte bug do repositório', () async {
      final r =
          await AcceptInviteUsecase(
            repository:
                _RepoQueLanca<
                  AcceptedTenantUser,
                  AcceptInviteParameters,
                  AcceptInviteError
                >(),
          )(
            const AcceptInviteParameters(
              token: 't',
              username: 'u',
              email: 'a@b.com',
              password: 'p',
            ),
          );

      expect((r as Failure).error, isA<AcceptInesperado>());
    });
  });

  group('usuarios', () {
    test('listTenantUsers converte bug do repositório', () async {
      final r = await ListTenantUsersUsecase(
        repository:
            _RepoQueLanca<List<TenantUser>, NoParams, TenantUsuariosError>(),
      )(noParams);

      expect((r as Failure).error, isA<UsuariosInesperado>());
    });

    test('updateTenantUser converte bug do repositório', () async {
      final r = await UpdateTenantUserUsecase(
        repository:
            _RepoQueLanca<
              Unit,
              UpdateTenantUserParameters,
              TenantUsuariosError
            >(),
      )(const UpdateTenantUserParameters(userId: 1));

      expect((r as Failure).error, isA<UsuariosInesperado>());
    });
  });

  group('config', () {
    test('getMyTenantConfig converte bug do repositório', () async {
      final r = await GetMyTenantConfigUsecase(
        repository: _RepoQueLanca<TenantConfig, NoParams, TenantConfigError>(),
      )(noParams);

      expect((r as Failure).error, isA<ConfigInesperado>());
    });

    test('updateMyTenantConfig converte bug do repositório', () async {
      final r = await UpdateMyTenantConfigUsecase(
        repository:
            _RepoQueLanca<
              Unit,
              UpdateMyTenantConfigParameters,
              TenantConfigError
            >(),
      )(const UpdateMyTenantConfigParameters(config: _config));

      expect((r as Failure).error, isA<ConfigInesperado>());
    });
  });
}
