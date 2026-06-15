import 'package:core_module/src/no_op/auth_service_no_op.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthServiceNoOp', () {
    test('executa checkCurrentUser sem erros', () async {
      final auth = AuthServiceNoOp();
      expect(auth.checkCurrentUser(), completes);
    });
  });
}
