import 'package:core_module/core_module.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Implementação real do `LocalStorageService` sobre `flutter_secure_storage`.
///
/// No Web/WASM o backend é o `localStorage` criptografado via Web Crypto
/// (exige HTTPS — garantido pelo Caddy). O contrato expõe `read` **síncrono**,
/// mas o secure storage é assíncrono; resolvemos com um cache em memória
/// hidratado no [init] (boot), atualizado a cada `write`/`delete`.
///
/// Segurança (Web): só valores não sensíveis ao XSS devem persistir aqui — no
/// escopo do login, apenas o **refresh token** (rotaciona + reuso detectado no
/// servidor). O access token nunca é persistido.
final class SecureLocalStorageService implements LocalStorageService {
  final FlutterSecureStorage _storage;
  final Map<String, String> _cache = {};

  SecureLocalStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              webOptions: WebOptions(
                dbName: 'smartcore_admin',
                publicKey: 'smartcore_admin_auth',
              ),
            );

  @override
  Future<void> init() async {
    final tudo = await _storage.readAll();
    _cache
      ..clear()
      ..addAll(tudo);
  }

  @override
  Future<void> write(String key, String value) async {
    _cache[key] = value;
    await _storage.write(key: key, value: value);
  }

  @override
  String? read(String key) => _cache[key];

  @override
  Future<void> delete(String key) async {
    _cache.remove(key);
    await _storage.delete(key: key);
  }
}
