import 'package:return_success_or_error/return_success_or_error.dart';

/// Parâmetros das operações do wizard — só dados.

/// Checagem de endereço.
final class SlugParameters extends Parameters {
  final String slug;
  const SlugParameters({required this.slug});
}

/// Operações sem entrada (listar planos, listar provedores).
final class SemParametros extends Parameters {
  const SemParametros();
}

/// Passo 1. **Nunca entra em log**: carrega a senha. O `toString` herdado de
/// `Object` não expõe campos, e é de propósito que não há um sobrescrito — o
/// `mapError` recebe este objeto como contexto.
final class IniciarCadastroParameters extends Parameters {
  final String nome;
  final String slug;
  final String email;
  final String senha;
  final String telefone;

  const IniciarCadastroParameters({
    required this.nome,
    required this.slug,
    required this.email,
    required this.senha,
    this.telefone = '',
  });
}

/// Passo 2.
final class SelecionarPlanoParameters extends Parameters {
  final String tenantId;
  final String signupToken;
  final int planoId;

  const SelecionarPlanoParameters({
    required this.tenantId,
    required this.signupToken,
    required this.planoId,
  });
}

/// Passo 3. `credencial` é o código de ativação quando o provedor pede um —
/// também não entra em log.
final class ConfirmarPagamentoParameters extends Parameters {
  final String tenantId;
  final String signupToken;
  final String provedorId;
  final String credencial;

  const ConfirmarPagamentoParameters({
    required this.tenantId,
    required this.signupToken,
    required this.provedorId,
    this.credencial = '',
  });
}

/// Passo 4 (acompanhamento).
final class StatusCadastroParameters extends Parameters {
  final String tenantId;
  final String signupToken;

  const StatusCadastroParameters({
    required this.tenantId,
    required this.signupToken,
  });
}
