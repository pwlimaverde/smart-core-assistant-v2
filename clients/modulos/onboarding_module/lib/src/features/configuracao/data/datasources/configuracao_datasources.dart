import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/configuracao_models.dart';
import '../../domain/parameters/configuracao_parameters.dart';

/// Datasources da configuração guiada: só I/O e a tradução protobuf → domínio.
///
/// Diferente dos do cadastro, estes usam o `AdminServiceClient` — já existe
/// sessão, e o token vai no interceptor. O `tenant_id` nunca é enviado: o
/// servidor o tira das claims.

final class CriarConexaoDatasource
    implements Datasource<ConexaoWhatsapp, CriarConexaoParameters> {
  final AdminServiceClient _client;

  const CriarConexaoDatasource({required this._client});

  @override
  Future<ConexaoWhatsapp> call(CriarConexaoParameters parameters) async {
    final resp = await _client.createMyWhatsappInstance(
      CreateMyWhatsappInstanceRequest(instanceName: parameters.nome),
    );
    return ConexaoWhatsapp(
      id: resp.id,
      nome: resp.instanceName,
      provedor: resp.provider,
    );
  }
}

final class EstadoConexaoDatasource
    implements Datasource<EstadoConexao, EstadoConexaoParameters> {
  final AdminServiceClient _client;

  const EstadoConexaoDatasource({required this._client});

  @override
  Future<EstadoConexao> call(EstadoConexaoParameters parameters) async {
    final resp = await _client.getMyWhatsappInstanceStatus(
      GetMyWhatsappInstanceStatusRequest(id: parameters.id),
    );
    return EstadoConexao(estado: resp.connectionState, qrCode: resp.qrCode);
  }
}

final class CriarDepartamentoDatasource
    implements Datasource<Departamento, CriarDepartamentoParameters> {
  final AdminServiceClient _client;

  const CriarDepartamentoDatasource({required this._client});

  @override
  Future<Departamento> call(CriarDepartamentoParameters parameters) async {
    final resp = await _client.createMyDepartamento(
      CreateMyDepartamentoRequest(
        nome: parameters.nome,
        descricao: parameters.descricao,
      ),
    );
    return Departamento(id: resp.id, nome: resp.nome);
  }
}

final class DefinirPersonaDatasource
    implements Datasource<Unit, PersonaParameters> {
  final AdminServiceClient _client;

  const DefinirPersonaDatasource({required this._client});

  @override
  Future<Unit> call(PersonaParameters parameters) async {
    await _client.setMyBotPersona(
      SetMyBotPersonaRequest(
        personaBot: parameters.personaBot,
        botAgentName: parameters.nomeDoAgente,
      ),
    );
    return unit;
  }
}

final class ProgressoDatasource
    implements Datasource<ProgressoOnboarding, ProgressoParameters> {
  final AdminServiceClient _client;

  const ProgressoDatasource({required this._client});

  @override
  Future<ProgressoOnboarding> call(ProgressoParameters parameters) async {
    final resp = await _client.setOnboardingProgress(
      SetOnboardingProgressRequest(
        passo: parameters.passo,
        concluido: parameters.concluido,
      ),
    );
    return ProgressoOnboarding(
      passo: resp.passo,
      concluido: resp.concluido,
    );
  }
}
