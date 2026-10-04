import 'dart:io';

import 'package:velopack_flutter/velopack_flutter.dart' as velopack;

import 'update_checker.dart';

/// Variável de ambiente que troca o feed em tempo de execução. Existe para o
/// teste ponta a ponta do CI (feed local com uma versão "falsa" mais nova);
/// quem consegue definir variáveis no processo do usuário já executa código
/// como ele, então não abre porta nova.
const kFeedUrlEnv = 'SMARTCORE_UPDATE_FEED_URL';

/// Monta o [UpdateChecker] do desktop. [feedUrlPadrao] vem do
/// `--dart-define=SMARTCORE_UPDATE_FEED_URL` do build.
UpdateChecker criarUpdateChecker(String feedUrlPadrao) {
  final override = Platform.environment[kFeedUrlEnv]?.trim() ?? '';
  return UpdateChecker(
    gateway: _VelopackFlutterGateway(),
    feedUrl: override.isNotEmpty ? override : feedUrlPadrao,
    suportado: Platform.isWindows,
  );
}

class _VelopackFlutterGateway implements VelopackGateway {
  @override
  bool get instalado {
    // Layout do Velopack: <raiz>\Update.exe e <raiz>\current\<app>.exe.
    final pastaDoExe = File(Platform.resolvedExecutable).parent;
    final updateExe = File(
      '${pastaDoExe.parent.path}${Platform.pathSeparator}Update.exe',
    );
    return updateExe.existsSync();
  }

  @override
  Future<void> inicializar(String feedUrl) =>
      velopack.initializeVelopack(url: feedUrl);

  @override
  Future<bool> haAtualizacao() => velopack.isUpdateAvailable();

  @override
  Future<void> atualizarEReiniciar() => velopack.updateAndRestart();
}
