import 'package:core_module/core_module.dart';

/// `LocalStorageService` que vive só na memória do processo.
///
/// É o armazenamento de "não manter conectado" fora da Web: no desktop não há
/// `sessionStorage`, e o equivalente mais fiel a "esquecer ao fechar" é não
/// gravar nada em disco.
final class MemoriaLocalStorageService implements LocalStorageService {
  final Map<String, String> _dados = {};

  @override
  Future<void> init() async {}

  @override
  Future<void> write(String key, String value) async => _dados[key] = value;

  @override
  String? read(String key) => _dados[key];

  @override
  Future<void> delete(String key) async => _dados.remove(key);
}
