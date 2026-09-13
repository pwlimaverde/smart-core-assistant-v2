import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/integracoes_errors.dart';
import '../model/atividade.dart';
import '../model/mcp_grant.dart';
import '../parameters/integracoes_parameters.dart';

void _logBug(String operacao, Object exception, StackTrace stackTrace) =>
    developer.log(
      'process de $operacao quebrou',
      name: 'tenant_module.integracoes',
      error: exception,
      stackTrace: stackTrace,
    );

final class ListMcpGrantsUsecase
    extends
        UsecaseBaseCallData<
          List<McpGrant>,
          List<McpGrant>,
          NoParams,
          IntegracoesError
        > {
  const ListMcpGrantsUsecase({required super.repository});

  @override
  ProcessData<List<McpGrant>, List<McpGrant>, NoParams, IntegracoesError>
  get process => _process;

  @override
  IntegracoesError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('listMcpGrants', exception, stackTrace);
    return const IntegracoesInesperado();
  }

  /// Regra da feature: os que **podem alterar dados** primeiro e, dentro de cada
  /// grupo, os usados mais recentemente no topo.
  ///
  /// A tela existe para o usuário reconhecer o que está conectado e cortar o que
  /// não deveria estar. Nessa leitura, um agente que envia mensagem a clientes
  /// importa mais que um que só lê o painel — e um que foi usado hoje importa
  /// mais que um esquecido há três meses.
  static ReturnSuccessOrError<List<McpGrant>, IntegracoesError> _process(
    List<McpGrant> data,
    NoParams parameters,
  ) {
    final ordenados = [...data]
      ..sort((a, b) {
        if (a.podeAlterar != b.podeAlterar) return a.podeAlterar ? -1 : 1;
        final usoA = a.lastUsedAt ?? a.createdAt;
        final usoB = b.lastUsedAt ?? b.createdAt;
        return usoB.compareTo(usoA);
      });
    return Success(List.unmodifiable(ordenados));
  }
}

/// Desconecta um aplicativo.
///
/// O sucesso devolve a **janela de revogação em minutos**, vinda do servidor:
/// desconectar corta o refresh token na hora, mas o access token em curso só
/// morre no `exp`. Esse número é configuração do backend, e a tela precisa dizer
/// o valor real — não um número escrito à mão no Dart, que deixaria de bater no
/// dia em que a configuração mudasse.
final class RevokeMcpGrantUsecase
    extends
        UsecaseBaseCallData<
          int,
          int,
          RevokeMcpGrantParameters,
          IntegracoesError
        > {
  const RevokeMcpGrantUsecase({required super.repository});

  @override
  ProcessData<int, int, RevokeMcpGrantParameters, IntegracoesError>
  get process => _process;

  @override
  IntegracoesError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('revokeMcpGrant', exception, stackTrace);
    return const IntegracoesInesperado();
  }

  static ReturnSuccessOrError<int, IntegracoesError> _process(
    int data,
    RevokeMcpGrantParameters parameters,
  ) => Success(data);
}

/// A atividade do tenant (B3). Passthrough: a ordem (mais recente primeiro) já
/// vem do servidor, que é quem pagina.
final class ListarAtividadeUsecase
    extends
        UsecaseBaseCallData<
          List<Atividade>,
          List<Atividade>,
          ListarAtividadeParameters,
          IntegracoesError
        > {
  const ListarAtividadeUsecase({required super.repository});

  @override
  ProcessData<
    List<Atividade>,
    List<Atividade>,
    ListarAtividadeParameters,
    IntegracoesError
  >
  get process => _process;

  @override
  IntegracoesError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('listarAtividade', exception, stackTrace);
    return const IntegracoesInesperado();
  }

  static ReturnSuccessOrError<List<Atividade>, IntegracoesError> _process(
    List<Atividade> data,
    ListarAtividadeParameters parameters,
  ) => Success(List.unmodifiable(data));
}
