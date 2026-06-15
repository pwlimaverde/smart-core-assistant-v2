import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:presentation_module/src/error_message_mapper.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

void main() {
  group('ErrorMessageMapper', () {
    test('mapeia erros de domínio para mensagens amigáveis em pt-br', () {
      expect(
        ErrorMessageMapper.map(const ErrorUnauthorized()),
        'Sessão expirada. Entre novamente.',
      );
      expect(
        ErrorMessageMapper.map(const ErrorAuth()),
        'E-mail ou senha inválidos.',
      );
      expect(
        ErrorMessageMapper.map(const ErrorValidation()),
        'Verifique os dados informados.',
      );
      expect(
        ErrorMessageMapper.map(const ErrorNetwork()),
        'Não foi possível conectar. Tente novamente.',
      );
      expect(
        ErrorMessageMapper.map(const ErrorGeneric(message: 'Erro x')),
        'Ocorreu um erro inesperado. Tente novamente.',
      );
    });
  });
}
