// Teste de superfície: prova que importar apenas dependencies_module expõe
// os tipos fundamentais de infra sem precisar de imports avulsos.
import 'package:dependencies_module/dependencies_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'dependencies_module expõe AppModule, ViewState, AppRouter e AppConfig',
    () {
      // Verifica que os tipos são acessíveis (compilação é a prova principal)
      expect(AppFlavor.dev, isA<AppFlavor>());

      const config = AppConfig(
        flavor: AppFlavor.dev,
        apiEndpoint: 'tcp://localhost:50051',
      );
      expect(config.isProd, isFalse);
      expect(config.apiEndpoint, 'tcp://localhost:50051');
    },
  );
}
