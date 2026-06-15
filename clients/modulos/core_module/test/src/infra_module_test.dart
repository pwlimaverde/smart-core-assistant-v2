import 'package:api_client/api_client.dart';
import 'package:app_config/app_config.dart';
import 'package:core_module/core_module.dart';
import 'package:core_module/src/infra_module.dart';
import 'package:core_module/src/no_op/auth_service_no_op.dart';
import 'package:core_module/src/no_op/local_storage_service_no_op.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:get_it_module/get_it_module.dart';
import 'package:mocktail/mocktail.dart';
import 'package:navigation_module/navigation_module.dart';

class MockLocalStorageService extends Mock implements LocalStorageService {}
class MockApiClient extends Mock implements ApiClient {}
class MockAuthService extends Mock implements AuthService {}

void main() {
  final getIt = GetIt.instance;

  group('InfraModule Binds', () {
    const config = AppConfig(
      flavor: AppFlavor.dev,
      apiEndpoint: 'http://localhost',
    );

    tearDown(() {
      getIt.reset();
    });

    test('registra singletons necessários via globalBinds', () {
      final module = InfraModule(config);
      final injector = Injector(getIt);

      module.globalBinds(injector);

      expect(getIt.isRegistered<AppConfig>(), isTrue);
      expect(getIt.isRegistered<BootState>(), isTrue);
      expect(getIt.isRegistered<SessionService>(), isTrue);

      expect(getIt<AppConfig>(), equals(config));
    });
  });

  group('InfraModule BootTasks', () {
    const config = AppConfig(
      flavor: AppFlavor.dev,
      apiEndpoint: 'http://localhost',
    );

    late MockLocalStorageService mockStorage;
    late MockApiClient mockApiClient;
    late MockAuthService mockAuthService;

    setUp(() {
      mockStorage = MockLocalStorageService();
      mockApiClient = MockApiClient();
      mockAuthService = MockAuthService();

      getIt.registerSingleton<LocalStorageService>(mockStorage);
      getIt.registerSingleton<ApiClient>(mockApiClient);
      getIt.registerSingleton<AuthService>(mockAuthService);
    });

    tearDown(() {
      getIt.reset();
    });

    test('executa bootTasks na ordem e invoca serviços', () async {
      when(() => mockStorage.init()).thenAnswer((_) async {});
      when(() => mockApiClient.connect()).thenAnswer((_) async {});
      when(() => mockAuthService.checkCurrentUser()).thenAnswer((_) async {});

      final module = InfraModule(config);
      final tasks = module.bootTasks();

      expect(tasks.length, 3);
      expect(tasks[0].stage, BootStage.infra);
      expect(tasks[1].stage, BootStage.infra);
      expect(tasks[2].stage, BootStage.session);

      await tasks[0].run();
      await tasks[1].run();
      await tasks[2].run();

      verify(() => mockStorage.init()).called(1);
      verify(() => mockApiClient.connect()).called(1);
      verify(() => mockAuthService.checkCurrentUser()).called(1);
    });
  });
}
