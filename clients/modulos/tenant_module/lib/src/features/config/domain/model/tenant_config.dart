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

  /// B4 — abaixo disto a resposta da IA vira transferência, mesmo com o
  /// modelo confiante. Decimal em string ("0.5"); vazio = herda o global;
  /// "0" = veto desligado.
  final String confiancaMinimaTransferencia;

  /// B4 — a partir disto a IA responde sem revisão, e é também o piso para
  /// um valor extraído entrar na ficha. Vazio = herda o global (0.8).
  final String confiancaMinimaAutomatica;

  /// O que o servidor guarda e nenhuma tela editava até a paridade do MCP:
  /// prompts do negócio, tipos de entidade, marca, fuso, idioma e os
  /// interruptores de análise, transcrição, pesquisa e inatividade.
  final ConfigAvancada avancada;

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
    this.confiancaMinimaTransferencia = '',
    this.confiancaMinimaAutomatica = '',
    this.avancada = const ConfigAvancada(),
  });
}

/// Configuração avançada do tenant. Gravada por um RPC próprio e parcial
/// (`UpdateMyConfigAvancada`): o que não muda aqui não é tocado.
///
/// `null` nos interruptores e nos minutos = o negócio herda o padrão global.
class ConfigAvancada {
  /// JSON dos tipos de entidade que a IA extrai (objeto `{tipo: descrição}`
  /// ou lista de nomes). Vazio = nenhum.
  final String tiposDeEntidadeJson;

  /// Prompts deste negócio, por cima dos globais (`PROMPT_*` → texto).
  final Map<String, String> prompts;
  final String marca;
  final String corPrimaria;
  final String corSecundaria;
  final String fuso;
  final String idioma;
  final bool? analisePrevia;
  final bool? pesquisaSatisfacao;
  final String msgPesquisaSatisfacao;
  final int? minutosInatividade;
  final bool? transcricao;

  const ConfigAvancada({
    this.tiposDeEntidadeJson = '',
    this.prompts = const {},
    this.marca = '',
    this.corPrimaria = '',
    this.corSecundaria = '',
    this.fuso = '',
    this.idioma = '',
    this.analisePrevia,
    this.pesquisaSatisfacao,
    this.msgPesquisaSatisfacao = '',
    this.minutosInatividade,
    this.transcricao,
  });
}

/// Os prompts que o assistente consulta — os mesmos da v1. Um prompt do
/// negócio só vale para as chaves daqui; o resto herda o global.
const promptsConhecidos = <String, String>{
  'PROMPT_REGRAS_RESPOSTA': 'Regras de resposta',
  'PROMPT_REGRAS_TRANSFERENCIA': 'Regras de transferência',
  'PROMPT_TEMPLATE_USER_RAG': 'Modelo da pergunta com o contexto',
  'PROMPT_SYSTEM_ANALISE_PREVIA_MENSAGEM': 'Análise prévia (sistema)',
  'PROMPT_HUMAN_ANALISE_PREVIA_MENSAGEM': 'Análise prévia (pergunta)',
  'PROMPT_INTENT_SYSTEM': 'Intenções (instruções)',
  'PROMPT_INTENT_FOOTER': 'Intenções (rodapé)',
  'PROMPT_SENTIMENTO_SYSTEM': 'Análise de sentimento',
  'PROMPT_INTERPRET_MEDIA_IMAGE': 'Interpretação de imagem',
  'PROMPT_INTERPRET_MEDIA_VIDEO': 'Interpretação de vídeo',
  'PROMPT_INTERPRET_MEDIA_DOCUMENT': 'Leitura de documento',
  'PROMPT_TRANSCRIBE_RESUMO': 'Resumo da transcrição de áudio',
  'PROMPT_SYSTEM_ANALISE_CONTEUDO': 'Análise de conteúdo (sistema)',
  'PROMPT_HUMAN_ANALISE_CONTEUDO': 'Análise de conteúdo (pergunta)',
  'PROMPT_SYSTEM_MELHORIA_CONTEUDO': 'Melhoria de conteúdo (sistema)',
  'PROMPT_HUMAN_MELHORIA_CONTEUDO': 'Melhoria de conteúdo (pergunta)',
};
