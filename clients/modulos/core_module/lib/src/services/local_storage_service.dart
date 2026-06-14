/// Contrato de armazenamento local persistente.
abstract interface class LocalStorageService {
  Future<void> init();
  Future<void> write(String key, String value);
  String? read(String key);
  Future<void> delete(String key);
}
