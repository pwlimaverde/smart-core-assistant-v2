import 'package:app_config/app_config.dart';

/// Cliente único de comunicação com o backend (gRPC/gRPC-Web em fase futura).
abstract interface class ApiClient {
  Future<void> connect();
}

/// Stub estrutural: `connect()` é no-op. NÃO loga segredos — só endpoint/status.
final class ApiClientStub implements ApiClient {
  final AppConfig config;
  const ApiClientStub({required this.config});

  @override
  Future<void> connect() async {
    if (config.enableLogging) {
      // ignore: avoid_print
      print(
        'ApiClient.connect → endpoint=${config.apiEndpoint} status=stub-ok',
      );
    }
  }
}
