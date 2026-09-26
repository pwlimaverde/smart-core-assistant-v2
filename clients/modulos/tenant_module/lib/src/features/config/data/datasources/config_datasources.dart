import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/tenant_config.dart';
import '../../domain/parameters/config_parameters.dart';

/// Lê a configuração do tenant da sessão.
final class GetMyTenantConfigDatasource
    implements Datasource<TenantConfig, NoParams> {
  final proto.AdminServiceClient _client;

  const GetMyTenantConfigDatasource({required this._client});

  @override
  Future<TenantConfig> call(NoParams parameters) async {
    final resp = await _client.getMyTenantConfig(
      proto.GetMyTenantConfigRequest(),
    );
    return TenantConfig(
      dadosEmpresa: resp.dadosEmpresa,
      personaBot: resp.personaBot,
      botAgentName: resp.botAgentName,
      msgFallback: resp.msgFallback,
      msgSemInfo: resp.msgSemInfo,
      msgTransferencia: resp.msgTransferencia,
      llmClass: resp.llmClass,
      model: resp.model,
      llmTemperature: resp.llmTemperature,
      transcriptionProvider: resp.transcriptionProvider,
      transcriptionModel: resp.transcriptionModel,
      visionProvider: resp.visionProvider,
      visionModel: resp.visionModel,
      embeddingsClass: resp.embeddingsClass,
      embeddingsModel: resp.embeddingsModel,
      chunkSize: resp.chunkSize,
      chunkOverlap: resp.chunkOverlap,
      similarityThreshold: resp.similarityThreshold,
      vectorDistanceThreshold: resp.vectorDistanceThreshold,
      confiancaMinimaTransferencia: resp.confiancaMinimaTransferencia,
      confiancaMinimaAutomatica: resp.confiancaMinimaAutomatica,
      apiKeys: {for (final e in resp.apiKeys) e.key: e.value},
      avancada: ConfigAvancada(
        tiposDeEntidadeJson: resp.entityTypesJson,
        prompts: {for (final p in resp.prompts) p.chave: p.texto},
        marca: resp.brandName,
        corPrimaria: resp.primaryColor,
        corSecundaria: resp.secondaryColor,
        fuso: resp.timezone,
        idioma: resp.languageCode,
        analisePrevia: resp.hasAnalisePreviaHabilitada()
            ? resp.analisePreviaHabilitada
            : null,
        pesquisaSatisfacao: resp.hasPesquisaSatisfacaoAtiva()
            ? resp.pesquisaSatisfacaoAtiva
            : null,
        msgPesquisaSatisfacao: resp.msgPesquisaSatisfacao,
        minutosInatividade: resp.hasMinutosInatividadeEncerra()
            ? resp.minutosInatividadeEncerra
            : null,
        transcricao: resp.hasTranscriptionEnabled()
            ? resp.transcriptionEnabled
            : null,
      ),
    );
  }
}

/// Grava a configuração do tenant da sessão.
final class UpdateMyTenantConfigDatasource
    implements Datasource<Unit, UpdateMyTenantConfigParameters> {
  final proto.AdminServiceClient _client;

  const UpdateMyTenantConfigDatasource({required this._client});

  @override
  Future<Unit> call(UpdateMyTenantConfigParameters parameters) async {
    final config = parameters.config;
    await _client.updateMyTenantConfig(
      proto.UpdateMyTenantConfigRequest(
        dadosEmpresa: config.dadosEmpresa,
        personaBot: config.personaBot,
        botAgentName: config.botAgentName,
        msgFallback: config.msgFallback,
        msgSemInfo: config.msgSemInfo,
        msgTransferencia: config.msgTransferencia,
        llmClass: config.llmClass,
        model: config.model,
        llmTemperature: config.llmTemperature,
        transcriptionProvider: config.transcriptionProvider,
        transcriptionModel: config.transcriptionModel,
        visionProvider: config.visionProvider,
        visionModel: config.visionModel,
        embeddingsClass: config.embeddingsClass,
        embeddingsModel: config.embeddingsModel,
        chunkSize: config.chunkSize,
        chunkOverlap: config.chunkOverlap,
        similarityThreshold: config.similarityThreshold,
        vectorDistanceThreshold: config.vectorDistanceThreshold,
        confiancaMinimaTransferencia: config.confiancaMinimaTransferencia,
        confiancaMinimaAutomatica: config.confiancaMinimaAutomatica,
        // As chaves de API são cifradas no servidor (AES-256-GCM); daqui saem em
        // claro pelo canal TLS e nunca são logadas.
        apiKeys: [
          for (final e in config.apiKeys.entries)
            proto.ApiKeyEntry(key: e.key, value: e.value),
        ],
      ),
    );
    return unit;
  }
}

/// Grava a configuração avançada do tenant da sessão.
final class UpdateConfigAvancadaDatasource
    implements Datasource<Unit, UpdateConfigAvancadaParameters> {
  final proto.AdminServiceClient _client;

  const UpdateConfigAvancadaDatasource({required this._client});

  @override
  Future<Unit> call(UpdateConfigAvancadaParameters parameters) async {
    final a = parameters.avancada;
    await _client.updateMyConfigAvancada(
      proto.UpdateMyConfigAvancadaRequest(
        entityTypesJson: a.tiposDeEntidadeJson.trim().isEmpty
            ? '{}'
            : a.tiposDeEntidadeJson,
        prompts: [
          for (final e in a.prompts.entries)
            proto.PromptDoTenant(chave: e.key, texto: e.value),
          for (final chave in parameters.promptsRemovidos)
            if (!a.prompts.containsKey(chave))
              proto.PromptDoTenant(chave: chave, texto: ''),
        ],
        // Vazio não vai: o servidor recusa cor fora de #RRGGBB, e "sem
        // valor" aqui é "não mexer".
        brandName: a.marca.isEmpty ? null : a.marca,
        primaryColor: a.corPrimaria.isEmpty ? null : a.corPrimaria,
        secondaryColor: a.corSecundaria.isEmpty ? null : a.corSecundaria,
        timezone: a.fuso.isEmpty ? null : a.fuso,
        languageCode: a.idioma.isEmpty ? null : a.idioma,
        analisePreviaHabilitada: a.analisePrevia,
        pesquisaSatisfacaoAtiva: a.pesquisaSatisfacao,
        msgPesquisaSatisfacao: a.msgPesquisaSatisfacao,
        minutosInatividadeEncerra: a.minutosInatividade ?? 0,
        transcriptionEnabled: a.transcricao,
      ),
    );
    return unit;
  }
}
