import 'package:admin_module/src/features/windows_downloads/data/datasources/windows_downloads_datasources.dart';
import 'package:admin_module/src/features/windows_downloads/data/repositories/windows_downloads_repositories.dart';
import 'package:admin_module/src/features/windows_downloads/domain/errors/windows_downloads_errors.dart';
import 'package:admin_module/src/features/windows_downloads/domain/model/windows_download_link.dart';
import 'package:admin_module/src/features/windows_downloads/domain/parameters/windows_downloads_parameters.dart';
import 'package:admin_module/src/features/windows_downloads/domain/usecases/windows_downloads_usecases.dart';
import 'package:admin_module/src/features/windows_downloads/presentation/controllers/windows_downloads_controller.dart';
import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../support/admin_grpc_mock.dart';

/// Feature `windows_downloads`: cadeia real (Datasource → Repository → Usecase →
/// Controller) sobre o stub gRPC mockado. A página fica de fora pelo mesmo
/// motivo da `AuditPage`: importa `package:web`, que não carrega na VM.
void main() {
  late MockAdminClient client;

  setUpAll(registrarFallbacksDoAdmin);
  setUp(() => client = MockAdminClient());

  GetWindowsDownloadLinkUsecase usecase() => GetWindowsDownloadLinkUsecase(
    repository: GetWindowsDownloadLinkRepository(
      datasource: GetWindowsDownloadLinkDatasource(client: client),
    ),
  );

  proto.GetWindowsDownloadLinkResponse resposta({int? expiraEmMs}) =>
      proto.GetWindowsDownloadLinkResponse(
        url: 'https://rel.exemplo/download/0.2.0-beta.1/App-Setup.exe?t=abc',
        version: '0.2.0-beta.1',
        fileName: 'App-Setup.exe',
        sizeBytes: Int64(5 * 1024 * 1024),
        sha256: 'a' * 64,
        releaseNotesMd: 'Primeira beta',
        expiresAtMs: Int64(
          expiraEmMs ??
              DateTime.now()
                  .add(const Duration(minutes: 5))
                  .millisecondsSinceEpoch,
        ),
      );

  test(
    'sucesso: converte a resposta e envia canal beta + versão vazia',
    () async {
      when(
        () => client.getWindowsDownloadLink(any()),
      ).thenAnswer((_) => respostaGrpc(resposta()));

      final r = await usecase()(const GetWindowsDownloadLinkParameters());

      final link =
          (r as Success<WindowsDownloadLink, WindowsDownloadsError>).value;
      expect(link.version, '0.2.0-beta.1');
      expect(link.fileName, 'App-Setup.exe');
      expect(link.sizeBytes, 5 * 1024 * 1024);
      expect(link.releaseNotesMd, 'Primeira beta');
      expect(link.validoEm(), isTrue);

      final req =
          verify(
                () => client.getWindowsDownloadLink(captureAny()),
              ).captured.single
              as proto.GetWindowsDownloadLinkRequest;
      expect(req.channel, 'beta');
      expect(req.version, '');
    },
  );

  test('link que já chegou vencido vira erro, não botão quebrado', () async {
    when(
      () => client.getWindowsDownloadLink(any()),
    ).thenAnswer((_) => respostaGrpc(resposta(expiraEmMs: 1)));

    final r = await usecase()(const GetWindowsDownloadLinkParameters());

    expect((r as Failure).error, isA<WindowsDownloadsInesperado>());
  });

  final matriz = <String, (proto.GrpcError, Type)>{
    'unauthenticated': (
      proto.GrpcError.unauthenticated('x'),
      WindowsDownloadsSessaoExpirada,
    ),
    'permissionDenied': (
      proto.GrpcError.permissionDenied('x'),
      WindowsDownloadsAcessoNegado,
    ),
    'invalidArgument': (
      proto.GrpcError.invalidArgument('x'),
      WindowsDownloadsCanalInvalido,
    ),
    'failedPrecondition': (
      proto.GrpcError.failedPrecondition('x'),
      WindowsDownloadsNaoConfigurado,
    ),
    'notFound': (proto.GrpcError.notFound('x'), WindowsDownloadsSemRelease),
    'unavailable': (
      proto.GrpcError.unavailable('x'),
      WindowsDownloadsIndisponivel,
    ),
    'resourceExhausted': (
      proto.GrpcError.resourceExhausted('x'),
      WindowsDownloadsIndisponivel,
    ),
    'alreadyExists': (
      proto.GrpcError.alreadyExists('x'),
      WindowsDownloadsInesperado,
    ),
    'internal': (proto.GrpcError.internal('boom'), WindowsDownloadsInesperado),
  };

  for (final MapEntry(key: nome, value: (erroGrpc, esperado))
      in matriz.entries) {
    test('$nome -> $esperado', () async {
      when(
        () => client.getWindowsDownloadLink(any()),
      ).thenAnswer((_) => falhaGrpc(erroGrpc));

      final r = await usecase()(const GetWindowsDownloadLinkParameters());

      final erro = (r as Failure).error as WindowsDownloadsError;
      expect(erro.runtimeType, esperado);
      expect(erro.message, isNot(contains('boom')));
    });
  }

  test('exceção fora do transporte também vira erro da feature', () async {
    when(
      () => client.getWindowsDownloadLink(any()),
    ).thenAnswer((_) => falhaGrpc(StateError('quebrou')));

    final r = await usecase()(const GetWindowsDownloadLinkParameters());

    expect((r as Failure).error, isA<WindowsDownloadsInesperado>());
  });

  test('controller: sucesso emite SuccessState com o link', () async {
    when(
      () => client.getWindowsDownloadLink(any()),
    ).thenAnswer((_) => respostaGrpc(resposta()));
    final controller = WindowsDownloadsController(getLinkUsecase: usecase());
    addTearDown(controller.close);

    await controller.gerarLink();

    expect(
      controller.state,
      isA<SuccessState<WindowsDownloadLink>>().having(
        (s) => s.data.fileName,
        'fileName',
        'App-Setup.exe',
      ),
    );
  });

  test(
    'controller: falha emite ErrorState com a mensagem da feature',
    () async {
      when(() => client.getWindowsDownloadLink(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.failedPrecondition('sem segredo')),
      );
      final controller = WindowsDownloadsController(getLinkUsecase: usecase());
      addTearDown(controller.close);

      await controller.gerarLink();

      expect(
        controller.state,
        isA<ErrorState<WindowsDownloadLink>>().having(
          (s) => s.error,
          'error',
          isA<WindowsDownloadsNaoConfigurado>(),
        ),
      );
    },
  );

  group('WindowsDownloadLink', () {
    WindowsDownloadLink link({int tamanho = 0, String sha = ''}) =>
        WindowsDownloadLink(
          url: 'u',
          version: 'v',
          fileName: 'f',
          sizeBytes: tamanho,
          sha256: sha,
          releaseNotesMd: '',
          expiresAtMs: 1000,
        );

    test('tamanho formatado em B, KB e MB', () {
      expect(link(tamanho: 512).tamanhoFormatado, '512 B');
      expect(link(tamanho: 2048).tamanhoFormatado, '2.0 KB');
      expect(link(tamanho: 3 * 1024 * 1024).tamanhoFormatado, '3.0 MB');
    });

    test('sha curto não quebra com hash pequeno', () {
      expect(link(sha: 'abc').sha256Curto, 'abc');
      expect(link(sha: 'b' * 64).sha256Curto, '${'b' * 16}…');
    });

    test('validade compara com o relógio informado', () {
      final l = link();
      expect(l.validoEm(DateTime.fromMillisecondsSinceEpoch(999)), isTrue);
      expect(l.validoEm(DateTime.fromMillisecondsSinceEpoch(1000)), isFalse);
    });
  });
}
