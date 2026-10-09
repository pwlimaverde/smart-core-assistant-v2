import 'dart:developer' as developer;
import 'dart:io';

/// Até a 0.2.0-beta.3 a sessão ficou em `%APPDATA%\com.example\smart_core_tenant`.
/// O `flutter_secure_storage_windows` monta essa pasta com o CompanyName e o
/// ProductName do `Runner.rc`, e o rebranding trocou os dois. Sem copiar, quem
/// atualiza perde o login.
const _pastaAntiga = r'com.example\smart_core_tenant';
const _pastaAtual = r'Smart Core\Smart Core Tenant';

Future<void> migrarSessaoDaVersaoAntiga() async {
  final appData = Platform.environment['APPDATA'];
  if (appData == null || appData.isEmpty) return;
  await copiarCofres(
    origem: Directory('$appData\\$_pastaAntiga'),
    destino: Directory('$appData\\$_pastaAtual'),
  );
}

/// Copia só os `.secure` que o destino ainda não tem. Nunca sobrescreve: se a
/// pessoa já entrou na versão nova, vale o login dela. Falha não derruba o boot.
Future<void> copiarCofres({
  required Directory origem,
  required Directory destino,
}) async {
  try {
    if (!await origem.exists()) return;
    await destino.create(recursive: true);
    await for (final entrada in origem.list()) {
      if (entrada is! File || !entrada.path.endsWith('.secure')) continue;
      final nome = entrada.uri.pathSegments.last;
      final alvo = File('${destino.path}${Platform.pathSeparator}$nome');
      if (await alvo.exists()) continue;
      await entrada.copy(alvo.path);
    }
  } catch (e, s) {
    developer.log(
      'falha ao migrar a sessão da versão anterior',
      name: 'smart_core_tenant.sessao',
      error: e,
      stackTrace: s,
    );
  }
}
