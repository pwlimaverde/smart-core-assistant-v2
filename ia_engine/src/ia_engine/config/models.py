"""`RuntimeConfig`: a config do tenant resolvida pelo servidor Rust.

Espelha o `RuntimeConfigDto` de `data_postgres/src/config_publisher.rs`, que o
Rust publica em `tenant:config:<uuid>` no Redis. Os nomes dos campos são
contrato entre os dois lados — renomear aqui sem renomear lá quebra a
deserialização em runtime, não em build.

Por que a config não vem no request: o Rust é o único que lê o Postgres e
resolve a cascata `TenantConfig > CoreSettings` (ver
`doc_dev/modelagem_dados/gerenciamento_configuracoes_ia.md`). Assim o payload
gRPC de cada mensagem de WhatsApp carrega só o `tenant_id` — chave de API e
prompt de sistema não trafegam a cada interação.
"""

from __future__ import annotations

from pydantic import BaseModel, Field

from ia_engine.domain.models import LlmProviderSpec

# Mapeia o nome de classe LangChain que a config carrega (herança da v1:
# `ChatGroq`, `OpenAIEmbeddings`) para o slug de provedor que
# `init_chat_model`/`init_embeddings` esperam. O lado Rust faz a mesma
# normalização em `provider_e_api_key_de`; aqui ela é refeita porque agora é o
# `ia_engine` quem monta o `LlmProviderSpec`.
_SLUG_POR_FRAGMENTO: tuple[tuple[str, str], ...] = (
    ("groq", "groq"),
    ("google", "google_genai"),
    ("gemini", "google_genai"),
)
_SLUG_PADRAO = "openai"


def _slug_provedor(class_name: str) -> str:
    """Converte nome de classe LangChain em slug de provedor.

    Sem correspondência cai em `openai`, que é o comportamento do lado Rust —
    manter os dois iguais evita que a mesma config resolva para provedores
    diferentes dependendo de quem pergunta.
    """
    lower = (class_name or "").lower()
    for fragmento, slug in _SLUG_POR_FRAGMENTO:
        if fragmento in lower:
            return slug
    return _SLUG_PADRAO


class RuntimeConfig(BaseModel):
    """Config consolidada de um tenant, com todos os fallbacks já aplicados."""

    tenant_id: str

    # Prompts de IA
    dados_empresa: str = ""
    persona_bot: str = ""
    bot_agent_name: str = ""

    # Mensagens automáticas
    msg_fallback: str = ""
    msg_sem_info: str = ""
    msg_transferencia: str = ""

    # LLM
    llm_class: str = ""
    model: str = ""
    llm_temperature: float = 0.0

    # Transcrição de áudio
    transcription_provider: str = ""
    transcription_model: str = ""
    transcription_enabled: bool = False

    # Visão computacional
    vision_provider: str = ""
    vision_model: str = ""

    # Embeddings e RAG
    embeddings_class: str = ""
    embeddings_model: str = ""
    chunk_size: int = 0
    chunk_overlap: int = 0

    # Thresholds
    similarity_threshold: float = 0.0
    vector_distance_threshold: float = 0.0

    # Chaves de API (decifradas pelo Rust antes de publicar)
    openai_api_key: str = ""
    groq_api_key: str = ""
    google_api_key: str = ""

    # Overrides de prompt (chave ausente => default do código, ver `prompt()`)
    prompts: dict[str, str] = Field(default_factory=dict)

    # ------------------------------------------------------------------ API
    def prompt(self, chave: str, padrao: str) -> str:
        """Texto do prompt `chave`, ou `padrao` quando não há override.

        O default vive no código de cada datasource de propósito: uma chave não
        semeada no banco não pode deixar a IA sem prompt, e a suíte de testes
        roda sem Redis nenhum.
        """
        valor = self.prompts.get(chave, "")
        return valor if valor.strip() else padrao

    def spec_llm(self) -> LlmProviderSpec:
        """Provedor de chat resolvido a partir de `llm_class`/`model`."""
        provider = _slug_provedor(self.llm_class)
        return LlmProviderSpec(
            provider=provider,
            model=self.model,
            api_key=self._api_key_de(provider),
            temperature=self.llm_temperature,
        )

    def spec_embeddings(self) -> LlmProviderSpec:
        """Provedor de embeddings — pode diferir do LLM (ex.: Gemini para chat,
        OpenAI para embeddings), por isso resolve a chave separadamente."""
        provider = _slug_provedor(self.embeddings_class)
        return LlmProviderSpec(
            provider=provider,
            model=self.embeddings_model,
            api_key=self._api_key_de(provider),
        )

    def spec_vision(self) -> LlmProviderSpec:
        """Provedor de visão. `vision_provider` já é um slug na config (a v1
        gravava 'google'/'openai' aqui, não nome de classe), mas passa pela
        mesma normalização por segurança."""
        provider = _slug_provedor(self.vision_provider)
        return LlmProviderSpec(
            provider=provider,
            model=self.vision_model,
            api_key=self._api_key_de(provider),
        )

    def spec_transcription(self) -> LlmProviderSpec:
        """Provedor de transcrição (tipicamente Groq/Whisper)."""
        provider = _slug_provedor(self.transcription_provider)
        return LlmProviderSpec(
            provider=provider,
            model=self.transcription_model,
            api_key=self._api_key_de(provider),
        )

    def _api_key_de(self, provider: str) -> str:
        match provider:
            case "groq":
                return self.groq_api_key
            case "google_genai":
                return self.google_api_key
            case _:
                return self.openai_api_key
