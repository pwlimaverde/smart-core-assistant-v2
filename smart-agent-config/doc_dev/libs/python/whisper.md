# Whisper (openai-whisper) e Transcrição via API

- **Versão Recomendada (Local):** 20231117 (ou wrapper `faster-whisper` 1.0.1)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-07-17
- **Propósito no Projeto:** Transcrição de mensagens de voz e arquivos de áudio (gravados pelo cliente no WhatsApp) em texto para análise cognitiva e exibição no chat. Suporta tanto processamento local quanto via API remota.
- **Documentação Oficial:**
  - Local: [https://github.com/openai/whisper](https://github.com/openai/whisper)
  - OpenAI API: [https://developers.openai.com/api/docs/guides/speech-to-text](https://developers.openai.com/api/docs/guides/speech-to-text)
  - Groq API: [https://console.groq.com/docs/speech-to-text](https://console.groq.com/docs/speech-to-text)

---

## 1. Contexto e Uso no Projeto

No Smart Core Assistant v2, o `worker` Rust identifica áudios recebidos (`audioMessage`) e aciona a transcrição. Se o inquilino preferir processamento local para evitar latência e custos de nuvem, o `ia_engine` pode inicializar o modelo **Whisper** localmente.

Dada a restrição de recursos da VM Hostinger (CPU-only, sem placas GPU Nvidia dedicadas), recomenda-se o uso da biblioteca **`faster-whisper`** (implementação otimizada em C++ usando CTranslate2) com o modelo **`base`** ou **`tiny`** para reduzir consumo de RAM e CPU.

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Transcrição de Áudio (faster-whisper)
Utilize `faster-whisper` para carregar o modelo de transcrição e execute-a de forma thread-safe assíncrona, liberando o runtime do gRPC/HTTP de bloqueios.

```python
from faster_whisper import WhisperModel
import io
import asyncio
from concurrent.futures import ThreadPoolExecutor

# Instancia o modelo na inicialização global do app
# model_size "base" balanceia bem precisão em português e consumo de CPU
# compute_type "int8" é ideal para CPU-only
model = WhisperModel("base", device="cpu", compute_type="int8")

# Executor de thread pool para operações pesadas de CPU
executor = ThreadPoolExecutor(max_workers=2)

def _transcribe_sync(audio_bytes: bytes) -> str:
    """Execução síncrona pesada do Whisper."""
    # Transforma o buffer de bytes em stream compatível
    audio_file = io.BytesIO(audio_bytes)
    
    # Executa a transcrição
    segments, info = model.transcribe(audio_file, beam_size=5, language="pt")
    
    # Junta os segmentos em um único texto estruturado
    text_segments = [segment.text for segment in segments]
    return " ".join(text_segments).strip()

async def transcribe_audio_async(audio_bytes: bytes) -> str:
    """Invoca o transcritor local via thread pool assíncrona."""
    loop = asyncio.get_running_loop()
    # Executa a transcrição pesada em outra thread para não bloquear a thread assíncrona
    text = await loop.run_in_executor(
        executor, 
        _transcribe_sync, 
        audio_bytes
    )
    return text
```

### 2.2 Tratamento de Idioma e Detecção
O Whisper realiza auto-detecção de idioma por padrão. No entanto, por se tratar de um atendimento em português (Brasil), especifique explicitamente o parâmetro `language="pt"` na chamada. Isso reduz a latência (o modelo pula a fase de detecção de linguagem) e evita que o modelo tente traduzir ou transcrever áudios com sotaques regionais para outros idiomas.

### 2.3 Resiliência e Fallback
O carregamento inicial do Whisper no disco pode falhar ou demorar na primeira execução (download do modelo de ~140MB). 
- Certifique-se de que os modelos de áudio sejam baixados previamente na etapa de build/deploy da VM Hostinger.
- Tenha uma API de fallback (como OpenAI Whisper API remota) pronta para ser utilizada se a execução de CPU local falhar ou demorar mais do que o timeout esperado (ex: 8s).

---

## 3. Transcrição via API (N6.4)

A fase N6.4 implementará transcrição REAL de mensagens de voz do WhatsApp usando APIs remotas. Áudios do WhatsApp tipicamente chegam em formato **ogg/opus** e têm duração < 2 minutos.

### 3.1 OpenAI Audio Transcriptions API

**Endpoint:** `POST /v1/audio/transcriptions`

**Modelos disponíveis (2026):**

| Modelo | Qualidade | Preço (entrada) | Preço (saída) | Características |
|--------|-----------|-----------------|---------------|-----------------|
| `whisper-1` | Baseline | $0.02/min | — | Modelo original Whisper V2 aberto; velocidade boa |
| `gpt-4o-mini-transcribe` | Alta | ~$0.50/M tokens | — | Menor, mais rápido que gpt-4o; bom custo-benefício |
| `gpt-4o-transcribe` | Máxima | $2.50/M tokens | $10.00/M tokens | Melhor WER (word error rate), melhor reconhecimento de idiomas |
| `gpt-4o-transcribe-diarize` | Máxima + Speaker ID | $2.50/M tokens | $10.00/M tokens | Inclui identificação de quem fala (speaker diarization) |

**Especificações Técnicas:**
- **Tamanho máximo:** 25 MB
- **Formatos aceitos:** mp3, mp4, mpeg, mpga, m4a, wav, webm
- **Limitação ogg/opus:** Embora `ogg` conste como suportado, há relatos de incompatibilidade com áudios ogg/opus do WhatsApp. Recomenda-se converter para wav/mp4 antes de enviar.
- **Response formats:**
  - `whisper-1`: json, text, srt, verbose_json, vtt
  - `gpt-4o-transcribe*`: json, text
  - `gpt-4o-transcribe-diarize`: json, text, diarized_json

**Exemplo Python (SDK openai >= 1.0):**

```python
from openai import AsyncOpenAI
import io
import asyncio

client = AsyncOpenAI(api_key="sk-...")

async def transcribe_audio_openai_gpt4o(audio_bytes: bytes, language: str = "pt") -> dict:
    """
    Transcrição via gpt-4o-transcribe (melhor qualidade).
    
    Args:
        audio_bytes: conteúdo do áudio em bytes
        language: código ISO-639-1 (ex: "pt" para português)
    
    Returns:
        {"text": "transcrição completa", "language": "pt"}
    """
    audio_file = io.BytesIO(audio_bytes)
    audio_file.name = "audio.ogg"  # importante: fornecer extensão
    
    # Se ogg/opus falhar, converter para wav primeiro
    # (implementar ffmpeg-python ou pydub conforme necessário)
    
    transcription = await client.audio.transcriptions.create(
        model="gpt-4o-transcribe",
        file=audio_file,
        language=language,
        response_format="json",
        temperature=0.0
    )
    
    return {
        "text": transcription.text,
        "language": getattr(transcription, "language", language)
    }
```

**Latência esperada:** 2-10s dependendo do tamanho do áudio e carga da API.

### 3.2 Groq Speech-to-Text

**Endpoint:** `POST https://api.groq.com/openai/v1/audio/transcriptions` (OpenAI-compatible)

**Modelos disponíveis (2026):**

| Modelo | WER (Word Error Rate) | Preço | Características |
|--------|----------------------|-------|-----------------|
| `whisper-large-v3-turbo` | ~12% | $0.04/hora | Otimizado para velocidade (up to 4x mais rápido) |
| `whisper-large-v3` | ~10.3% | $0.111/hora | Máxima precisão; multilíngue |
| `distil-whisper-large-v3-en` | ~12% | Menor | Apenas inglês; mais leve |

**Especificações Técnicas:**
- **Tamanho máximo:** 25 MB (free tier), 100 MB (dev tier)
- **Formatos aceitos:** mp3, wav, m4a, **flac**, **ogg**, webm ✅ **Suporta ogg/opus natively**
- **Processamento:** Downsampled automaticamente a 16KHz mono
- **Response formats:** json, verbose_json, text
- **Parâmetros opcionais:** language (ISO-639-1), prompt (até 224 tokens), temperature, timestamps (segment ou word-level)

**Exemplo Python (compatível com SDK openai):**

```python
from openai import AsyncOpenAI
import io
import asyncio

# Cliente Groq via endpoint compatible com OpenAI
client = AsyncOpenAI(
    api_key="gsk_...",  # chave Groq
    base_url="https://api.groq.com/openai/v1"
)

async def transcribe_audio_groq(audio_bytes: bytes, language: str = "pt") -> dict:
    """
    Transcrição via Groq whisper-large-v3 (bom custo-benefício).
    Nativo suporte para ogg/opus do WhatsApp.
    
    Args:
        audio_bytes: conteúdo do áudio em bytes (ogg/opus funciona)
        language: código ISO-639-1
    
    Returns:
        {"text": "transcrição", "avg_logprob": <confidence>}
    """
    audio_file = io.BytesIO(audio_bytes)
    audio_file.name = "audio.ogg"
    
    transcription = await client.audio.transcriptions.create(
        model="whisper-large-v3-turbo",  # ou "whisper-large-v3" para máxima qualidade
        file=audio_file,
        language=language,
        response_format="json"
    )
    
    return {
        "text": transcription.text,
        "avg_logprob": getattr(transcription, "avg_logprob", None)  # confiança
    }
```

**Latência esperada:** 0.5-5s (Groq é notoriamente rápido).

### 3.3 Decisão: LangChain vs SDK Direto

**Status de wrappers LangChain:**
- `OpenAIWhisperParser`: Suporta whisper-1 e gpt-4o-transcribe, mas não gpt-4o-mini-transcribe nem parâmetros novos (temperature, timestamps word-level)
- `OpenAIWhisperParserLocal`: Para rodagem local (já documentado em 2.1)
- **Não há wrapper LangChain para Groq ou gpt-4o-transcribe-diarize**

**Recomendação:**
Use **SDK openai direto** (via AsyncOpenAI) para máxima compatibilidade com modelos novos e Groq. LangChain seria limitante para N6.4.

```python
# ❌ Evitar (limitado ao whisper-1)
from langchain_community.document_loaders.parsers import OpenAIWhisperParser

# ✅ Usar (flexível, suporta tudo)
from openai import AsyncOpenAI
```

### 3.4 Recomendação: Estratégia Híbrida para N6.4

Para o Smart Core Assistant v2, recomenda-se:

1. **Primary (padrão):** Groq `whisper-large-v3-turbo`
   - Nativo support para ogg/opus do WhatsApp ✅
   - Latência ultra-rápida (~1-2s para áudios < 2min)
   - Custo competitivo ($0.04/hora = ~$0.00067 por minuto de áudio)
   - WER aceitável (12%, comparável a gpt-4o-mini)

2. **Fallback:** OpenAI `gpt-4o-transcribe`
   - Melhor qualidade (WER 10%, reconhece sotaques/ruído melhor)
   - Custo maior (~$0.0417 por minuto baseado em 16kHz)
   - Use se Groq estiver indisponível ou para áudios críticos

3. **Local (opcional):** `faster-whisper` com modelo `base`
   - Zero custos de API, latência previsível
   - Ideal para modo offline/fallback completo
   - Tradeoff: CPU/RAM da VM, latência ~10-15s

**Implementação (pseudo-código):**

```python
async def transcribe_whatsapp_audio(audio_bytes: bytes, language: str = "pt") -> str:
    """Estratégia de fallback encadeada."""
    
    # 1. Tenta Groq (rápido, nativo ogg/opus)
    try:
        result = await transcribe_audio_groq(audio_bytes, language)
        return result["text"]
    except Exception as e_groq:
        logger.warning(f"Groq falhou: {e_groq}, tentando OpenAI...")
    
    # 2. Fallback: OpenAI gpt-4o-transcribe (qualidade)
    try:
        result = await transcribe_audio_openai_gpt4o(audio_bytes, language)
        return result["text"]
    except Exception as e_openai:
        logger.error(f"OpenAI falhou: {e_openai}, usando local...")
    
    # 3. Fallback: Local faster-whisper (modo offline)
    try:
        result = await transcribe_audio_local(audio_bytes, language)
        return result
    except Exception as e_local:
        logger.error(f"Todas as opções falharam: {e_local}")
        raise
```

---

## Histórico de Atualizações

- **2026-07-17:** Adicionada seção "Transcrição via API (N6.4)" com documentação de OpenAI gpt-4o-transcribe, Groq whisper-large-v3, recomendação SDK openai direto, estratégia híbrida de fallback. Confirmado suporte nativo ogg/opus em Groq.
- **2026-05-31:** Última revisão anterior da seção local (faster-whisper)
