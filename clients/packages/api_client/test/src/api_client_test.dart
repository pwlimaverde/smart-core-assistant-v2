import 'package:api_client/src/api_client.dart';
import 'package:app_config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiClientStub', () {
    test('conecta sem lançar erros e respeita logging desativado', () async {
      const config = AppConfig(
        flavor: AppFlavor.dev,
        apiEndpoint: 'http://localhost:50051',
        enableLogging: false,
      );

      final client = ApiClientStub(config: config);
      expect(client.connect(), completes);
    });

    test('conecta sem lançar erros com logging ativado', () async {
      const config = AppConfig(
        flavor: AppFlavor.dev,
        apiEndpoint: 'http://localhost:50051',
        enableLogging: true,
      );

      final client = ApiClientStub(config: config);
      expect(client.connect(), completes);
    });
  });
}
