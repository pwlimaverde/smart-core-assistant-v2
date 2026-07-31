import 'package:return_success_or_error/return_success_or_error.dart';

/// Parâmetros da configuração inicial guiada.

/// Cria a conexão de WhatsApp no provedor.
final class CriarConexaoParameters extends Parameters {
  final String nome;

  const CriarConexaoParameters({required this.nome});
}

/// Consulta o pareamento (estado + QR).
final class EstadoConexaoParameters extends Parameters {
  final int id;

  const EstadoConexaoParameters({required this.id});
}

/// Cria o primeiro departamento.
final class CriarDepartamentoParameters extends Parameters {
  final String nome;
  final String descricao;

  const CriarDepartamentoParameters({
    required this.nome,
    this.descricao = '',
  });
}

/// Registra o progresso no servidor.
final class ProgressoParameters extends Parameters {
  /// 5..8.
  final int passo;
  final bool concluido;

  const ProgressoParameters({required this.passo, this.concluido = false});
}

/// Define a persona do bot (passo 7). Reaproveita `UpdateMyTenantConfig`, que
/// exige o objeto inteiro — os demais campos vão como estão hoje.
final class PersonaParameters extends Parameters {
  final String personaBot;
  final String nomeDoAgente;

  const PersonaParameters({
    required this.personaBot,
    required this.nomeDoAgente,
  });
}
