import '../services/local_storage_service.dart';

/// Impl no-op do LocalStorageService (base estrutural sem storage real).
final class LocalStorageServiceNoOp implements LocalStorageService {
  final _store = <String, String>{};

  @override
  Future<void> init() async {}

  @override
  Future<void> write(String key, String value) async => _store[key] = value;

  @override
  String? read(String key) => _store[key];

  @override
  Future<void> delete(String key) async => _store.remove(key);
}
