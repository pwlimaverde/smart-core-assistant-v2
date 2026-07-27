import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/tenant_config.dart';
import '../../domain/parameters/tenant_config_parameters.dart';

/// Datasources da feature `tenant_config`: I/O gRPC e conversão protobuf →
/// domínio. Todos burros — sem `try/catch`, a exceção sobe crua para o
/// `mapError` do repositório correspondente.

/// Lê a configuração de IA/persona de um tenant.
final class GetTenantConfigDatasource
    implements Datasource<TenantConfig, GetTenantConfigParameters> {
  final proto.AdminServiceClient _client;

  const GetTenantConfigDatasource({required this._client});

  @override
  Future<TenantConfig> call(GetTenantConfigParameters parameters) async {
    final resp = await _client.getTenantConfig(
      proto.GetTenantConfigRequest(tenantId: parameters.tenantId),
    );

    final apiKeys = <String, String>{};
    for (final entry in resp.apiKeys) {
      apiKeys[entry.key] = entry.value;
    }

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
      apiKeys: apiKeys,
    );
  }
}

/// Grava a configuração de IA/persona de um tenant.
final class UpdateTenantConfigDatasource
    implements Datasource<Unit, UpdateTenantConfigParameters> {
  final proto.AdminServiceClient _client;

  const UpdateTenantConfigDatasource({required this._client});

  @override
  Future<Unit> call(UpdateTenantConfigParameters parameters) async {
    final apiKeysProto = <proto.ApiKeyEntry>[];
    parameters.config.apiKeys.forEach((k, v) {
      apiKeysProto.add(proto.ApiKeyEntry(key: k, value: v));
    });

    await _client.updateTenantConfig(
      proto.UpdateTenantConfigRequest(
        tenantId: parameters.tenantId,
        dadosEmpresa: parameters.config.dadosEmpresa,
        personaBot: parameters.config.personaBot,
        botAgentName: parameters.config.botAgentName,
        msgFallback: parameters.config.msgFallback,
        msgSemInfo: parameters.config.msgSemInfo,
        msgTransferencia: parameters.config.msgTransferencia,
        llmClass: parameters.config.llmClass,
        model: parameters.config.model,
        llmTemperature: parameters.config.llmTemperature,
        transcriptionProvider: parameters.config.transcriptionProvider,
        transcriptionModel: parameters.config.transcriptionModel,
        visionProvider: parameters.config.visionProvider,
        visionModel: parameters.config.visionModel,
        embeddingsClass: parameters.config.embeddingsClass,
        embeddingsModel: parameters.config.embeddingsModel,
        chunkSize: parameters.config.chunkSize,
        chunkOverlap: parameters.config.chunkOverlap,
        similarityThreshold: parameters.config.similarityThreshold,
        vectorDistanceThreshold: parameters.config.vectorDistanceThreshold,
        apiKeys: apiKeysProto,
      ),
    );
    return unit;
  }
}
