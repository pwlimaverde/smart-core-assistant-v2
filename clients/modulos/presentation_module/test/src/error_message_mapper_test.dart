import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:presentation_module/src/error_message_mapper.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Erros no formato de uma feature real: conjunto fechado, mensagem pt-br no
/// próprio caso, marcador declarando a natureza da falha.
sealed class _FeatureError extends AppError {
  const _FeatureError(super.message);
}

final class _SlugDuplicado extends _FeatureError {
  const _SlugDuplicado() : super('Slug já utilizado por outro tenant.');
}

final class _SemSessao extends _FeatureError with UnauthorizedFailure {
  const _SemSessao() : super('Sessão expirada. Entre novamente.');
}

final class _Indisponivel extends _FeatureError with NetworkFailure {
  const _Indisponivel() : super('Servidor indisponível. Tente novamente.');
}

/// O caso "inesperado" como ele **não** deveria ser escrito: com o texto da
/// exceção concatenado. Serve para provar que o mapper protege a tela mesmo
/// quando a feature erra a mão.
final class _InesperadoVazado extends _FeatureError with UnexpectedFailure {
  const _InesperadoVazado()
    : super(r'FileSystemException: C:\Users\alguem\token.json');
}

final class _SemMensagem extends _FeatureError {
  const _SemMensagem() : super('   ');
}

void main() {
  group('ErrorMessageMapper', () {
    test('usa a mensagem que a feature escreveu', () {
      expect(
        ErrorMessageMapper.map(const _SlugDuplicado()),
        'Slug já utilizado por outro tenant.',
      );
      expect(
        ErrorMessageMapper.map(const _SemSessao()),
        'Sessão expirada. Entre novamente.',
      );
      expect(
        ErrorMessageMapper.map(const _Indisponivel()),
        'Servidor indisponível. Tente novamente.',
      );
    });

    test('impõe mensagem genérica em erro marcado como inesperado', () {
      final exibida = ErrorMessageMapper.map(const _InesperadoVazado());

      expect(exibida, ErrorMessageMapper.mensagemGenerica);
      expect(
        exibida,
        isNot(contains('token.json')),
        reason: 'detalhe técnico nunca chega à tela, nem se o erro o carregar',
      );
      expect(exibida, isNot(contains('FileSystemException')));
    });

    test('ErrorGeneric da lib também cai na mensagem genérica', () {
      expect(
        ErrorMessageMapper.map(const ErrorGeneric('stack trace cru aqui')),
        ErrorMessageMapper.mensagemGenerica,
      );
    });

    test('erro sem mensagem útil cai na mensagem genérica', () {
      expect(
        ErrorMessageMapper.map(const _SemMensagem()),
        ErrorMessageMapper.mensagemGenerica,
      );
    });
  });
}
