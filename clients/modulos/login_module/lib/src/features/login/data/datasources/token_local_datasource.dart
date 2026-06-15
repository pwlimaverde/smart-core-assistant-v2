import 'package:core_module/core_module.dart';

/// Persistência do **refresh token** no armazenamento local seguro.
///
/// É o único token persistido (chave namespaced). O access token vive apenas
/// em memória no `SessionService`/`AuthServiceImpl`.
final class TokenLocalDatasource {
  static const String _refreshKey = 'smartcore_admin_auth_refresh_token';

  final LocalStorageService _storage;

  const TokenLocalDatasource({required this._storage});

  Future<void> writeRefresh(String token) =>
      _storage.write(_refreshKey, token);

  /// Lê o refresh persistido (boot → auto-login silencioso). `null` quando ausente.
  Future<String?> readRefresh() async => _storage.read(_refreshKey);

  Future<void> deleteRefresh() => _storage.delete(_refreshKey);
}
