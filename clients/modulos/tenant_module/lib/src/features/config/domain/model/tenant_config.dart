/// Configuração do próprio tenant (persona/prompts/providers). Mesma forma da
/// resposta usada pelo painel do superusuário (`GetTenantConfig`), mas aqui
/// resolvida pelo backend a partir do `tenant_id` da sessão (nunca passado
/// pelo cliente). `apiKeys` já vem mascarado do backend.
class TenantConfig {
  final String dadosEmpresa;
  final String personaBot;
  final String botAgentName;
  final String msgFallback;
  final String msgSemInfo;
  final String msgTransferencia;
  final String llmClass;
  final String model;
  final String llmTemperature;
  final String transcriptionProvider;
  final String transcriptionModel;
  final String visionProvider;
  final String visionModel;
  final String embeddingsClass;
  final String embeddingsModel;
  final int chunkSize;
  final int chunkOverlap;
  final String similarityThreshold;
  final String vectorDistanceThreshold;
  final Map<String, String> apiKeys;

  const TenantConfig({
    required this.dadosEmpresa,
    required this.personaBot,
    required this.botAgentName,
    required this.msgFallback,
    required this.msgSemInfo,
    required this.msgTransferencia,
    required this.llmClass,
    required this.model,
    required this.llmTemperature,
    required this.transcriptionProvider,
    required this.transcriptionModel,
    required this.visionProvider,
    required this.visionModel,
    required this.embeddingsClass,
    required this.embeddingsModel,
    required this.chunkSize,
    required this.chunkOverlap,
    required this.similarityThreshold,
    required this.vectorDistanceThreshold,
    required this.apiKeys,
  });
}
