import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ErrorLocalEngine', () {
    test('mensagem padrão quando nenhuma é informada', () {
      expect(const ErrorLocalEngine().message, 'Falha no motor local.');
    });

    test('igualdade por valor', () {
      const error1 = ErrorLocalEngine(message: 'Erro A');
      const error2 = ErrorLocalEngine(message: 'Erro A');
      const error3 = ErrorLocalEngine(message: 'Erro B');

      expect(error1, equals(error2));
      expect(error1, isNot(equals(error3)));
      expect(error1.hashCode, equals(error2.hashCode));
    });

    test('é igual a si mesma (identidade) e diferente de outro tipo de erro', () {
      const error = ErrorLocalEngine(message: 'x');
      expect(error == error, isTrue);
      expect(error, isNot(equals(const ErrorAuth(message: 'x'))));
    });

    test('copyWith preserva o tipo e atualiza a mensagem', () {
      const error = ErrorLocalEngine(message: 'original');
      final updated = error.copyWith(message: 'novo');

      expect(updated.message, 'novo');
      expect(updated, isA<ErrorLocalEngine>());
    });

    test('copyWith sem argumento mantém o valor original', () {
      const error = ErrorLocalEngine(message: 'mantido');
      expect(error.copyWith().message, 'mantido');
    });

    test('toString retorna formato correto', () {
      const error = ErrorLocalEngine(message: 'Erro MSG');
      expect(error.toString(), contains('ErrorLocalEngine - Erro MSG'));
    });
  });
}
