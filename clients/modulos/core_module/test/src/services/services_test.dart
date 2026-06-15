import 'package:core_module/core_module.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthService extends Mock implements AuthService {}
class MockLocalStorageService extends Mock implements LocalStorageService {}
class MockSessionService extends Mock implements SessionService {}

void main() {
  group('Core Module Services Contracts', () {
    test('contratos podem ser implementados e mockados', () {
      final auth = MockAuthService();
      final storage = MockLocalStorageService();
      final session = MockSessionService();

      expect(auth, isNotNull);
      expect(storage, isNotNull);
      expect(session, isNotNull);
    });
  });
}
