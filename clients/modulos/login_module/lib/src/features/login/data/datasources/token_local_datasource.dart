import 'package:core_module/core_module.dart';

import 'memoria_local_storage_service.dart';

/// Persistência do **refresh token** no armazenamento local seguro.
///
/// É o único token persistido (chave namespaced). O access token vive apenas
/// em memória no `SessionService`/`AuthServiceImpl` — o auto-login da abertura
/// é um refresh com este token, não a leitura de um access guardado.
///
/// Dois destinos, conforme o "manter conectado" escolhido no login:
///  - **persistente** (`localStorage` na Web, cofre do sistema no desktop):
///    sobrevive ao fechamento do navegador/app;
///  - **temporário** (`sessionStorage` na Web, memória no desktop): some quando
///    o navegador/app fecha.
///
/// O token fica em **um** dos dois, nunca nos dois: gravar num apaga o outro.
/// Assim a rotação do refresh (a cada renovação) preserva a escolha original
/// sem precisar guardá-la à parte.
final class TokenLocalDatasource {
  // Nome mantido desde a primeira versão: trocá-lo deslogaria quem já tem
  // sessão guardada no desktop. A separação entre apps na Web é feita pelo
  // prefixo do `SecureLocalStorageService`, não por esta chave.
  static const String _refreshKey = 'smartcore_admin_auth_refresh_token';

  final LocalStorageService _persistente;
  final LocalStorageService _temporario;
  Future<void>? _temporarioPronto;

  TokenLocalDatasource({
    required LocalStorageService storage,
    LocalStorageService? temporario,
  }) : _persistente = storage,
       _temporario = temporario ?? MemoriaLocalStorageService();

  /// O temporário não tem boot task própria: hidrata na primeira vez que é
  /// usado (o `init` do persistente já roda no `BootStage.infra`).
  Future<LocalStorageService> _temp() async {
    await (_temporarioPronto ??= _temporario.init());
    return _temporario;
  }

  /// Grava o refresh.
  ///
  /// [manterConectado] explícito (login) escolhe o destino. `null` (rotação no
  /// refresh) mantém o destino onde o token atual já está.
  Future<void> writeRefresh(String token, {bool? manterConectado}) async {
    final temp = await _temp();
    final persistir = manterConectado ?? temp.read(_refreshKey) == null;
    if (persistir) {
      await _persistente.write(_refreshKey, token);
      await temp.delete(_refreshKey);
    } else {
      await temp.write(_refreshKey, token);
      await _persistente.delete(_refreshKey);
    }
  }

  /// Lê o refresh guardado (boot → auto-login silencioso). `null` quando
  /// ausente.
  ///
  /// Recarrega o persistente antes de ler: o `SecureLocalStorageService` lê de
  /// um cache hidratado no boot, e na Web outra aba pode ter rotacionado o
  /// token depois disso. Usar a cópia velha é exatamente o reuso que faz o
  /// servidor revogar a sessão inteira.
  Future<String?> readRefresh() async {
    await _persistente.init();
    final persistido = _persistente.read(_refreshKey);
    if (persistido != null && persistido.isNotEmpty) return persistido;
    return (await _temp()).read(_refreshKey);
  }

  /// Apaga o refresh dos dois destinos (logout ou token recusado).
  Future<void> deleteRefresh() async {
    await _persistente.delete(_refreshKey);
    await (await _temp()).delete(_refreshKey);
  }
}
