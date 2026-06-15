import 'package:app_config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig', () {
    test('cria instância com propriedades corretas', () {
      const config = AppConfig(
        flavor: AppFlavor.dev,
        apiEndpoint: 'https://api-dev.smartcore.com',
        enableLogging: true,
      );

      expect(config.flavor, AppFlavor.dev);
      expect(config.apiEndpoint, 'https://api-dev.smartcore.com');
      expect(config.enableLogging, isTrue);
      expect(config.isProd, isFalse);
    });

    test('isProd retorna true apenas quando flavor for prod', () {
      const prodConfig = AppConfig(
        flavor: AppFlavor.prod,
        apiEndpoint: 'https://api.smartcore.com',
      );
      expect(prodConfig.isProd, isTrue);

      const devConfig = AppConfig(
        flavor: AppFlavor.dev,
        apiEndpoint: 'https://api-dev.smartcore.com',
      );
      expect(devConfig.isProd, isFalse);

      const stagingConfig = AppConfig(
        flavor: AppFlavor.staging,
        apiEndpoint: 'https://api-staging.smartcore.com',
      );
      expect(stagingConfig.isProd, isFalse);
    });
  });
}
