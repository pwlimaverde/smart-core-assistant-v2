# Whisper (openai-whisper)

- **Versão Recomendada:** 20231117 (ou wrapper `faster-whisper` 1.0.1)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
- **Propósito no Projeto:** Transcrição de mensagens de voz e arquivos de áudio locais (gravados pelo cliente no WhatsApp) em texto para análise cognitiva e exibição no chat.
- **Documentação Oficial:** [https://github.com/openai/whisper](https://github.com/openai/whisper)

---

## 1. Contexto e Uso no Projeto

No Smart Core Assistant v2, o `worker` Rust identifica áudios recebidos (`audioMessage`) e aciona a transcrição. Se o inquilino preferir processamento local para evitar latência e custos de nuvem, o `ai-engine` pode inicializar o modelo **Whisper** localmente.

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
