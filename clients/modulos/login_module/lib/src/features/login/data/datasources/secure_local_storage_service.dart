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
///
/// [prefixoWeb] é o prefixo das chaves no `localStorage`. O painel do
/// superusuário e o app do tenant são servidos da **mesma origem**
/// (`/v2/admin` e `/v2/tenant`), e com o mesmo prefixo um app sobrescrevia —
/// ou apagava, no logout — a sessão do outro. Cada app passa o seu.
///
/// [sessao] troca o `localStorage` pelo `sessionStorage` (apagado quando o
/// navegador fecha): é o modo "não manter conectado". Só tem efeito na Web — no
/// desktop o plugin ignora a opção, e por isso o `LoginModule` usa memória lá.
final class SecureLocalStorageService implements LocalStorageService {
  final FlutterSecureStorage _storage;
  final Map<String, String> _cache = {};

  SecureLocalStorageService({
    FlutterSecureStorage? storage,
    String prefixoWeb = 'smartcore_admin_auth',
    bool sessao = false,
  }) : _storage =
           storage ??
           FlutterSecureStorage(
             webOptions: WebOptions(
               dbName: 'smartcore_admin',
               publicKey: prefixoWeb,
               useSessionStorage: sessao,
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
