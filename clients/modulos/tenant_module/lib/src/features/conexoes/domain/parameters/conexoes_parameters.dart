import 'package:return_success_or_error/return_success_or_error.dart';

/// Identifica a conexão — usado por reconectar e remover.
final class ConexaoIdParameters extends Parameters {
  final int id;

  const ConexaoIdParameters({required this.id});
}

/// Nome da instância no provedor — precisa ser único entre todos os tenants,
/// e é o servidor quem recusa a repetição.
final class CriarConexaoParameters extends Parameters {
  final String nome;

  const CriarConexaoParameters({required this.nome});
}

/// Liga/desliga a resposta automática da IA para a conexão inteira (D3).
///
/// Não carrega `tenant_id`: o backend resolve o tenant pelas claims. Aceitar um
/// tenant do cliente seria deixar alguém calar o bot da conexão de outro.
final class RespostaBotParameters extends Parameters {
  final int id;
  final bool habilitado;

  const RespostaBotParameters({required this.id, required this.habilitado});
}

/// P7 — roteamento por conexão. `departamentoId = 0` desfaz o vínculo.
final class DepartamentoDaConexaoParameters extends Parameters {
  final int id;
  final int departamentoId;

  const DepartamentoDaConexaoParameters({
    required this.id,
    required this.departamentoId,
  });
}
