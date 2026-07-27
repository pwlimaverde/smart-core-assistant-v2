import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Feature fictícia que exercita os marcadores exatamente como uma feature real:
/// conjunto `sealed` fechado, cada caso declarando a sua natureza.
sealed class _ExemploError extends AppError {
  const _ExemploError(super.message);
}

final class _ExemploIndisponivel extends _ExemploError with NetworkFailure {
  const _ExemploIndisponivel() : super('Servidor indisponível.');
}

final class _ExemploSemSessao extends _ExemploError with UnauthorizedFailure {
  const _ExemploSemSessao() : super('Sessão expirada.');
}

final class _ExemploDadoInvalido extends _ExemploError with ValidationFailure {
  const _ExemploDadoInvalido() : super('Dados inválidos.');
}

final class _ExemploInesperado extends _ExemploError with UnexpectedFailure {
  const _ExemploInesperado() : super('Ocorreu um erro inesperado.');
}

/// Caso sem marcador: erro de negócio próprio da feature, que não tem natureza
/// transversal nenhuma — o tratamento genérico deve cair no `default`.
final class _ExemploRegraDeNegocio extends _ExemploError {
  const _ExemploRegraDeNegocio() : super('Limite do plano atingido.');
}

/// Reação transversal, escrita como a apresentação escreve: casa pelo marcador,
/// sem conhecer nenhum caso concreto da feature.
String _reagir(AppError error) => switch (error) {
  UnauthorizedFailure() => 'derrubar-sessao',
  ValidationFailure() => 'destacar-campo',
  NetworkFailure() => 'tentar-novamente',
  UnexpectedFailure() => 'reportar',
  _ => 'mostrar-mensagem',
};

void main() {
  group('marcadores de falha', () {
    test('cada marcador é reconhecido pelo tratamento transversal', () {
      expect(_reagir(const _ExemploSemSessao()), 'derrubar-sessao');
      expect(_reagir(const _ExemploDadoInvalido()), 'destacar-campo');
      expect(_reagir(const _ExemploIndisponivel()), 'tentar-novamente');
      expect(_reagir(const _ExemploInesperado()), 'reportar');
    });

    test('erro sem marcador cai no tratamento genérico', () {
      expect(_reagir(const _ExemploRegraDeNegocio()), 'mostrar-mensagem');
    });

    test('o marcador é um AppError — dá acesso à mensagem sem cast', () {
      const NetworkFailure falha = _ExemploIndisponivel();
      expect(falha.message, 'Servidor indisponível.');
    });

    test('marcador não interfere na igualdade herdada de AppError', () {
      expect(const _ExemploIndisponivel(), const _ExemploIndisponivel());
      expect(
        const _ExemploIndisponivel().hashCode,
        const _ExemploIndisponivel().hashCode,
      );
      expect(
        const _ExemploIndisponivel(),
        isNot(const _ExemploSemSessao()),
        reason: 'tipos diferentes não são iguais, mesmo herdando a mesma base',
      );
    });

    test('marcador não interfere no toString herdado', () {
      expect(
        const _ExemploSemSessao().toString(),
        '_ExemploSemSessao - Sessão expirada.',
      );
    });

    test('erro marcado trafega dentro de Failure e sobrevive à comparação', () {
      const ReturnSuccessOrError<int, _ExemploError> resultado =
          Failure(_ExemploIndisponivel());
      expect(resultado, const Failure<int, _ExemploError>(_ExemploIndisponivel()));
      switch (resultado) {
        case Success(:final value):
          fail('não deveria ser sucesso: $value');
        case Failure(:final error):
          expect(error, isA<NetworkFailure>());
      }
    });

    test('o switch sobre o conjunto sealed é exaustivo sem default', () {
      // Se um caso novo entrar em _ExemploError, este switch para de compilar —
      // é a garantia que a v3 traz e o motivo de o erro ser fechado por feature.
      String rotular(_ExemploError error) => switch (error) {
        _ExemploIndisponivel() => 'indisponivel',
        _ExemploSemSessao() => 'sem-sessao',
        _ExemploDadoInvalido() => 'dado-invalido',
        _ExemploInesperado() => 'inesperado',
        _ExemploRegraDeNegocio() => 'regra',
      };

      expect(rotular(const _ExemploRegraDeNegocio()), 'regra');
      expect(rotular(const _ExemploInesperado()), 'inesperado');
    });
  });
}
