import 'package:admin_module/src/features/usuarios/data/datasources/usuarios_datasources.dart';
import 'package:admin_module/src/features/usuarios/data/repositories/usuarios_repositories.dart';
import 'package:admin_module/src/features/usuarios/domain/errors/usuarios_errors.dart';
import 'package:admin_module/src/features/usuarios/domain/model/migracao_de_escopos.dart';
import 'package:admin_module/src/features/usuarios/domain/parameters/usuarios_parameters.dart';
import 'package:admin_module/src/features/usuarios/domain/usecases/usuarios_usecases.dart';
import 'package:admin_module/src/features/usuarios/presentation/controllers/usuarios_controller.dart';
import 'package:admin_module/src/features/usuarios/presentation/pages/usuarios_page.dart';
import 'package:api_client/api_client.dart' show GrpcError;
import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../support/admin_grpc_mock.dart';

MigrarEscoposUsecase _usecase(MockAdminClient client) => MigrarEscoposUsecase(
  repository: MigrarEscoposRepository(
    datasource: MigrarEscoposDatasource(client: client),
  ),
);

UsuariosController _controller(
  MockAdminClient client, {
  bool comMigracao = true,
}) => UsuariosController(
  listar: ListarUsuariosUsecase(
    repository: ListarUsuariosRepository(
      datasource: ListarUsuariosDatasource(client: client),
    ),
  ),
  definirAtivo: DefinirUsuarioAtivoUsecase(
    repository: DefinirUsuarioAtivoRepository(
      datasource: DefinirUsuarioAtivoDatasource(client: client),
    ),
  ),
  migrar: comMigracao ? _usecase(client) : null,
);

/// P18 — tornar explícitos os escopos que cada vínculo tem pelo papel.
void main() {
  late MockAdminClient client;

  setUpAll(() {
    registrarFallbacksDoAdmin();
    registerFallbackValue(proto.MigrarEscoposImplicitosRequest());
  });
  setUp(() => client = MockAdminClient());

  test('a prévia manda dry_run e ordena pelo maior grupo', () async {
    when(() => client.migrarEscoposImplicitos(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.MigrarEscoposImplicitosResponse(
          contagens: [
            proto.ContagemDeMigracao(
              tenantId: 't1',
              tenantNome: 'Loja A',
              papel: 'staff',
              quantidade: 1,
            ),
            proto.ContagemDeMigracao(
              tenantId: 't2',
              tenantNome: 'Loja B',
              papel: 'admin',
              quantidade: 3,
            ),
          ],
          total: 4,
          dryRun: true,
        ),
      ),
    );

    final r = await _usecase(client)(
      const MigrarEscoposParameters(simular: true),
    );

    final valor = (r as Success<ResultadoDaMigracao, UsuariosError>).value;
    expect(valor.simulacao, isTrue);
    expect(valor.total, 4);
    expect(valor.contagens.first.tenantNome, 'Loja B');
    final enviado =
        verify(
              () => client.migrarEscoposImplicitos(captureAny()),
            ).captured.single
            as proto.MigrarEscoposImplicitosRequest;
    expect(enviado.dryRun, isTrue);
  });

  test('recusa do servidor vira erro da feature', () async {
    when(
      () => client.migrarEscoposImplicitos(any()),
    ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));

    final r = await _controller(client).migrarEscopos(simular: false);

    expect(r, isA<Failure<ResultadoDaMigracao, UsuariosError>>());
  });

  test('sem o caso de uso, a tela não oferece a migração', () async {
    final c = _controller(client, comMigracao: false);

    expect(c.podeMigrarEscopos, isFalse);
    expect(
      await c.migrarEscopos(simular: true),
      isA<Failure<ResultadoDaMigracao, UsuariosError>>(),
    );
  });

  group('diálogo da prévia', () {
    Future<bool?> abrir(WidgetTester tester, ResultadoDaMigracao previa) async {
      bool? resposta;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                resposta = await showDialog<bool>(
                  context: context,
                  builder: (d) =>
                      DialogoDeMigracao(previa: previa, dialogContext: d),
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      return resposta;
    }

    testWidgets('lista os grupos e confirma com o total', (tester) async {
      await abrir(
        tester,
        const ResultadoDaMigracao(
          contagens: [
            GrupoAMigrar(
              tenantId: 't1',
              tenantNome: 'Loja A',
              papel: 'staff',
              quantidade: 2,
            ),
          ],
          total: 2,
          migrados: 0,
          pulados: 0,
          simulacao: true,
        ),
      );

      expect(find.text('Loja A'), findsOneWidget);
      expect(find.text('staff'), findsOneWidget);
      await tester.tap(find.text('Migrar 2'));
      await tester.pumpAndSettle();
      expect(find.byType(DialogoDeMigracao), findsNothing);
    });

    testWidgets('nada a migrar quando ninguém depende do papel', (
      tester,
    ) async {
      await abrir(
        tester,
        const ResultadoDaMigracao(
          contagens: [],
          total: 0,
          migrados: 0,
          pulados: 0,
          simulacao: true,
        ),
      );

      expect(find.text('Nada a migrar'), findsOneWidget);
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      expect(find.byType(DialogoDeMigracao), findsNothing);
    });
  });
}
