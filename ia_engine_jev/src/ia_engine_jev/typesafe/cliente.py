"""Único ponto que fala com a TypeSafe (Jev).

- A chave é da **plataforma**: CoreSetting `TYPESAFE_API_KEY`, decifrada pelo
  Rust e publicada no Redis com a config de cada tenant. Chega aqui por
  `api_key=` explícito; o container não tem a variável `TYPESAFE_API_KEY`
  (o SDK a leria sozinho).
- Retry com orçamento total curto: está no caminho da conversa, e cada nova
  tentativa cobra os tokens de novo. 422 (pergunta malformada) não é retentado:
  é erro nosso.
- Nada do `state`, das perguntas ou do corpo de erro vai para log ou span — o
  corpo pode ecoar a mensagem do cliente. Só status, request id, contagens.
"""

from __future__ import annotations

import hashlib
import time
from collections.abc import Mapping
from typing import Any, Protocol

from loguru import logger
from opentelemetry import metrics, trace
from opentelemetry.trace import Status, StatusCode

from ia_engine_jev.typesafe.tipos import (
    Escolha,
    Nivel,
    Pergunta,
    PerguntaChoice,
    PerguntaNoul,
    PerguntaScore,
    RespostaJev,
)

_SERVICE_NAME = "ia_engine_jev"
MODELO_PADRAO = "jev-1.13.0"


# ------------------------------------------------------------------ erros
class JevErro(Exception):
    """Falha ao consultar o Jev. `codigo` vai para o span e a métrica."""

    codigo = "jev_erro"


class JevNaoConfigurado(JevErro):
    """Sem `TYPESAFE_API_KEY` na configuração geral."""

    codigo = "jev_nao_configurado"


class JevIndisponivel(JevErro):
    """Rede, timeout ou 5xx depois do retry."""

    codigo = "jev_indisponivel"


class JevChaveInvalida(JevErro):
    """401/403: a chave da plataforma está errada ou revogada."""

    codigo = "jev_chave_invalida"


class JevPerguntaInvalida(JevErro):
    """400/422: a pergunta que montamos está malformada — bug nosso."""

    codigo = "jev_pergunta_invalida"


class JevLimite(JevErro):
    """429 depois do retry: limite de requisições da conta."""

    codigo = "jev_limite"


# ------------------------------------------------------------- contrato
class ClienteJev(Protocol):
    """O que as features precisam: uma requisição com várias perguntas."""

    async def perguntar(
        self,
        etapa: str,
        state: Any,
        perguntas: Mapping[str, Pergunta],
    ) -> RespostaJev: ...


# ------------------------------------------------------------- métricas
class _Metricas:
    def __init__(self) -> None:
        medidor = metrics.get_meter(_SERVICE_NAME)
        self.requisicoes = medidor.create_counter(
            "smartcore_jev_requisicoes_total",
            description="Requisições ao Jev, por etapa e status",
        )
        self.duracao = medidor.create_histogram(
            "smartcore_jev_duracao_ms",
            unit="ms",
            description="Duração de uma requisição ao Jev",
        )
        self.tokens = medidor.create_counter(
            "smartcore_jev_tokens_total",
            description="Tokens de entrada cobrados pelo Jev, por etapa",
        )
        self.limite = medidor.create_counter(
            "smartcore_jev_limite_total",
            description="Requisições recusadas por limite (429) depois do retry",
        )


_metricas: _Metricas | None = None


def _obter_metricas() -> _Metricas:
    # Preguiçoso pelo mesmo motivo do `telemetry.py`: criado depois do setup.
    global _metricas
    if _metricas is None:
        _metricas = _Metricas()
    return _metricas


# ------------------------------------------------------------ conversão
def para_sdk(pergunta: Pergunta) -> Any:
    """Converte uma pergunta nossa no objeto do SDK."""
    from typesafe_sdk import Choice, Noul, NoulCriteria, Score

    match pergunta:
        case PerguntaChoice():
            return Choice(
                instructions=pergunta.instrucoes, criteria=dict(pergunta.criterios)
            )
        case PerguntaNoul():
            criterios = None
            if pergunta.sim is not None or pergunta.nao is not None:
                criterios = NoulCriteria(true=pergunta.sim, false=pergunta.nao)
            return Noul(instructions=pergunta.instrucoes, criteria=criterios)
        case PerguntaScore():
            return Score(
                instructions=pergunta.instrucoes, criteria=list(pergunta.niveis)
            )


def de_sdk(resposta: Any, duracao_ms: int) -> RespostaJev:
    """Converte a `SystemOneResponse` do SDK em `RespostaJev`."""
    uso = getattr(resposta, "usage", None)
    tokens = getattr(uso, "input_tokens", None) or 0
    return RespostaJev(
        escolhas={
            k: Escolha(
                escolha=str(v.choice),
                confianca=float(v.confidence),
                probabilidades=dict(v.probabilities or {}),
            )
            for k, v in resposta.choices.items()
        },
        nouls={k: float(v.noul) for k, v in resposta.nouls.items()},
        niveis={
            k: Nivel(
                valor=float(v.score),
                confianca=float(v.confidence),
                probabilidades={int(n): float(p) for n, p in v.probabilities.items()},
            )
            for k, v in resposta.scores.items()
        },
        tokens_entrada=int(tokens),
        modelo=str(getattr(resposta, "model", "") or ""),
        duracao_ms=duracao_ms,
    )


def traduzir_erro(exc: BaseException) -> JevErro:
    """Exceção do SDK → erro nosso, sem carregar a mensagem (pode ecoar dados)."""
    from typesafe_sdk import (
        TypeSafeAuthenticationError,
        TypeSafeBadRequestError,
        TypeSafePermissionDeniedError,
        TypeSafeRateLimitError,
        TypeSafeUnprocessableEntityError,
    )

    match exc:
        case TypeSafeAuthenticationError() | TypeSafePermissionDeniedError():
            return JevChaveInvalida("chave TypeSafe recusada")
        case TypeSafeUnprocessableEntityError() | TypeSafeBadRequestError():
            return JevPerguntaInvalida("pergunta ao Jev recusada como malformada")
        case TypeSafeRateLimitError():
            return JevLimite("limite de requisições da conta TypeSafe")
        case _:
            return JevIndisponivel(f"Jev indisponível ({type(exc).__name__})")


# -------------------------------------------------------------- cliente
class TypeSafeJev:
    """Cliente real. Um por (chave, modelo), reaproveitado entre RPCs."""

    def __init__(
        self,
        api_key: str,
        modelo: str = MODELO_PADRAO,
        *,
        orcamento_s: float = 2.0,
        timeout_s: float = 2.0,
    ) -> None:
        import httpx2
        from typesafe_sdk import AsyncTypeSafeClient, RetryPolicy

        self._modelo = modelo or MODELO_PADRAO
        politica = RetryPolicy(
            max_retries=2,
            backoff_initial=0.2,
            backoff_max=1.0,
            timeout=orcamento_s,
        )
        # HTTP/2: as requisições em paralelo (uma por trecho) dividem a
        # conexão. Sem o pacote `h2`, o httpx2 recusaria — cai no HTTP/1.1.
        try:
            http = httpx2.AsyncClient(http2=True, timeout=timeout_s)
        except ImportError:  # pragma: no cover - depende do extra instalado
            http = httpx2.AsyncClient(timeout=timeout_s)
        self._cliente = AsyncTypeSafeClient(
            api_key=api_key,
            model=self._modelo,
            retry=politica,
            http_client=http,
        )

    async def perguntar(
        self,
        etapa: str,
        state: Any,
        perguntas: Mapping[str, Pergunta],
    ) -> RespostaJev:
        from typesafe_sdk import TypeSafeAPIError, TypeSafeError

        m = _obter_metricas()
        tracer = trace.get_tracer(_SERVICE_NAME)
        with tracer.start_as_current_span("jev.requisicao") as span:
            span.set_attribute("jev.etapa", etapa)
            span.set_attribute("jev.perguntas", len(perguntas))
            span.set_attribute("jev.modelo", self._modelo)
            inicio = time.perf_counter()
            status = "ok"
            try:
                resposta = await self._cliente.system_one(
                    state=state,
                    questions={k: para_sdk(p) for k, p in perguntas.items()},
                )
            except TypeSafeError as exc:
                erro = traduzir_erro(exc)
                status = erro.codigo
                if isinstance(exc, TypeSafeAPIError):
                    span.set_attribute("http.status_code", exc.status)
                    if exc.request_id:
                        span.set_attribute("jev.request_id", exc.request_id)
                if isinstance(erro, JevLimite):
                    m.limite.add(1, {"etapa": etapa})
                span.set_status(Status(StatusCode.ERROR, erro.codigo))
                logger.warning(
                    "requisição ao Jev falhou",
                    etapa=etapa,
                    error_code=erro.codigo,
                    erro=type(exc).__name__,
                )
                raise erro from None
            finally:
                duracao_ms = int((time.perf_counter() - inicio) * 1000)
                span.set_attribute("jev.duracao_ms", duracao_ms)
                m.requisicoes.add(1, {"etapa": etapa, "status": status})
                m.duracao.record(duracao_ms, {"etapa": etapa})
            convertida = de_sdk(resposta, duracao_ms)
            span.set_attribute("jev.tokens_entrada", convertida.tokens_entrada)
            span.set_attribute("jev.modelo_respondeu", convertida.modelo)
            m.tokens.add(convertida.tokens_entrada, {"etapa": etapa})
            return convertida


class FabricaJev:
    """Clientes por (hash da chave, modelo): trocar a chave na configuração
    geral cria um cliente novo sem reiniciar o serviço."""

    def __init__(self) -> None:
        self._clientes: dict[tuple[str, str], ClienteJev] = {}

    def __call__(self, api_key: str, modelo: str) -> ClienteJev:
        if not (api_key or "").strip():
            raise JevNaoConfigurado("TYPESAFE_API_KEY vazia na configuração geral")
        chave = (hashlib.sha256(api_key.encode()).hexdigest(), modelo or MODELO_PADRAO)
        cliente = self._clientes.get(chave)
        if cliente is None:
            cliente = TypeSafeJev(api_key.strip(), modelo or MODELO_PADRAO)
            self._clientes[chave] = cliente
        return cliente


type FabricaDeClienteJev = Any
"""Qualquer chamável `(api_key, modelo) -> ClienteJev` (a fábrica real ou um
dublê de teste)."""
