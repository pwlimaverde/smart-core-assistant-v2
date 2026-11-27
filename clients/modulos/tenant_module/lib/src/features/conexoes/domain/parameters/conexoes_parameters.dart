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

  /// Provedor de QR escolhido na tela de Integrações. O padrão é o de antes
  /// desta tela existir.
  final String provedor;

  const CriarConexaoParameters({
    required this.nome,
    this.provedor = 'evolution',
  });
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

/// Conexão por credenciais: o provedor, o nome da conexão e os valores do
/// formulário que ele declarou (chave → valor).
final class ConectarCanalParameters extends Parameters {
  final String provedor;
  final String nome;
  final Map<String, String> valores;

  const ConectarCanalParameters({
    required this.provedor,
    required this.nome,
    required this.valores,
  });
}
