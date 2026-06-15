import 'package:core_module/src/no_op/local_storage_service_no_op.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalStorageServiceNoOp', () {
    test('salva e recupera dados localmente em memória', () async {
      final storage = LocalStorageServiceNoOp();
      expect(storage.init(), completes);
      
      await storage.write('k', 'v');
      expect(storage.read('k'), equals('v'));
      
      await storage.delete('k');
      expect(storage.read('k'), isNull);
    });
  });
}
