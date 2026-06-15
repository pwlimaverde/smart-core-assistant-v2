import 'package:flutter_test/flutter_test.dart';
import 'package:initial_loading_module/initial_loading_module.dart';

void main() {
  group('InitialLoadingModule', () {
    test('routes() retorna exatamente uma rota', () {
      final module = InitialLoadingModule();
      expect(module.routes(), hasLength(1));
    });

    test('routes() primeira rota tem path "/"', () {
      final module = InitialLoadingModule();
      expect(module.routes().first.path, '/');
    });

    test('bootTasks() retorna lista vazia (boot é responsabilidade do controller)', () {
      expect(InitialLoadingModule().bootTasks(), isEmpty);
    });
  });
}
