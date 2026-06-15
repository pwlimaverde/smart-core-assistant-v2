import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Auth Errors', () {
    group('ErrorAuth', () {
      test('igualdade por valor', () {
        const error1 = ErrorAuth(message: 'Erro A');
        const error2 = ErrorAuth(message: 'Erro A');
        const error3 = ErrorAuth(message: 'Erro B');

        expect(error1, equals(error2));
        expect(error1, isNot(equals(error3)));
        expect(error1.hashCode, equals(error2.hashCode));
      });

      test('copyWith preserva tipo e atualiza mensagem', () {
        const error = ErrorAuth(message: 'Erro original');
        final updated = error.copyWith(message: 'Novo erro');

        expect(updated.message, 'Novo erro');
        expect(updated, isA<ErrorAuth>());
      });

      test('copyWith sem argumento mantém valores', () {
        const error = ErrorAuth(message: 'Erro');
        final updated = error.copyWith();

        expect(updated.message, 'Erro');
      });

      test('toString retorna formato correto', () {
        const error = ErrorAuth(message: 'Erro MSG');
        expect(error.toString(), contains('ErrorAuth - Erro MSG'));
      });
    });

    group('ErrorUnauthorized', () {
      test('igualdade por valor', () {
        const error1 = ErrorUnauthorized(message: 'Erro A');
        const error2 = ErrorUnauthorized(message: 'Erro A');
        const error3 = ErrorUnauthorized(message: 'Erro B');

        expect(error1, equals(error2));
        expect(error1, isNot(equals(error3)));
        expect(error1.hashCode, equals(error2.hashCode));
      });

      test('copyWith', () {
        const error = ErrorUnauthorized(message: 'original');
        final updated = error.copyWith(message: 'novo');
        expect(updated.message, 'novo');
        expect(error.copyWith().message, 'original');
      });

      test('toString', () {
        const error = ErrorUnauthorized(message: 'msg');
        expect(error.toString(), contains('ErrorUnauthorized - msg'));
      });
    });

    group('ErrorNetwork', () {
      test('igualdade por valor', () {
        const error1 = ErrorNetwork(message: 'Erro A');
        const error2 = ErrorNetwork(message: 'Erro A');
        const error3 = ErrorNetwork(message: 'Erro B');

        expect(error1, equals(error2));
        expect(error1, isNot(equals(error3)));
      });

      test('copyWith', () {
        const error = ErrorNetwork(message: 'original');
        final updated = error.copyWith(message: 'novo');
        expect(updated.message, 'novo');
        expect(error.copyWith().message, 'original');
      });

      test('toString', () {
        const error = ErrorNetwork(message: 'msg');
        expect(error.toString(), contains('ErrorNetwork - msg'));
      });
    });

    group('ErrorValidation', () {
      test('igualdade por valor', () {
        const error1 = ErrorValidation(message: 'Erro A');
        const error2 = ErrorValidation(message: 'Erro A');
        const error3 = ErrorValidation(message: 'Erro B');

        expect(error1, equals(error2));
        expect(error1, isNot(equals(error3)));
      });

      test('copyWith', () {
        const error = ErrorValidation(message: 'original');
        final updated = error.copyWith(message: 'novo');
        expect(updated.message, 'novo');
        expect(error.copyWith().message, 'original');
      });

      test('toString', () {
        const error = ErrorValidation(message: 'msg');
        expect(error.toString(), contains('ErrorValidation - msg'));
      });
    });
  });
}
