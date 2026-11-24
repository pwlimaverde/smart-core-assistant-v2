"""Continuidade após limite de uso (ganchos + verificador do agendador).

Peça complementar do roteador (`roteador.py`). Dois papéis no mesmo arquivo:

1. Gancho do Claude Code (sem argumentos, JSON no stdin), registrado em
   `UserPromptSubmit`, `SessionStart`, `Stop`, `StopFailure` e `Notification`:
   - `UserPromptSubmit` guarda o último pedido (mascarado) da sessão;
   - `Stop` marca a tarefa como concluída;
   - `StopFailure` com erro retomável (`rate_limit`, `server_error`) marca a
     sessão como parada por limite e calcula quando retomar;
   - `Notification` `quota_auto_resume_fired` indica que o próprio Claude Code
     retomou (auto-continue nativo da sessão interativa): cancela a nossa;
   - `UserPromptSubmit`/`SessionStart` injetam os avisos pendentes (limite
     detectado, retomada feita, desistência) para o coordenador saber.
2. Verificador (`--verificar`), chamado por um timer do sistema (systemd no
   VPS, Agendador de Tarefas no Windows), que sobrevive ao fim da sessão:
   para cada sessão parada cujo horário chegou, roda
   `claude -p --resume <sessão> [--fork-session]` com a instrução de
   continuidade, registra o resultado e reagenda com backoff se o limite
   persistir, até `max_tentativas`/`teto_horas`.

Estado e log em `~/.claude/roteador-continuidade/` (ou
`ROTEADOR_CONTINUIDADE_DIR`): `estado.json`, `log.jsonl`, `status.txt` e
`config.json` (opcional, por máquina). Nada de segredo vai para lá: o pedido
passa pelo `mascarar` do roteador e é truncado.

Outros usos: `--status`, `--verificar --seco` (só diz o que faria) e
`--registrar-hooks <settings.json>` (instala os ganchos, com backup).
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import time
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path

DIR_HOOKS = Path(__file__).resolve().parent
sys.path.insert(0, str(DIR_HOOKS))
try:
    from roteador import MACHINE_PREFIX, mascarar
except Exception:  # noqa: BLE001 - sem o roteador, segue com máscara mínima
    MACHINE_PREFIX = os.getenv("ROTEADOR_MACHINE") or "LOCAL"

    def mascarar(texto: str) -> str:
        return re.sub(r"\b[A-Za-z0-9_\-]{32,}\b", "<valor-longo>", texto)


DIR_CLAUDE_USUARIO = Path(os.getenv("CLAUDE_CONFIG_DIR") or (Path.home() / ".claude"))
DIR_ESTADO = Path(os.getenv("ROTEADOR_CONTINUIDADE_DIR") or (DIR_CLAUDE_USUARIO / "roteador-continuidade"))
ARQ_ESTADO = DIR_ESTADO / "estado.json"
ARQ_LOG = DIR_ESTADO / "log.jsonl"
ARQ_STATUS = DIR_ESTADO / "status.txt"
ARQ_CONFIG_LOCAL = DIR_ESTADO / "config.json"
TRAVA_ESTADO = DIR_ESTADO / "estado.lock"
TRAVA_VERIFICACAO = DIR_ESTADO / "verificar.lock"
DIR_SESSOES = DIR_CLAUDE_USUARIO / "sessions"

# Prefixo da instrução de retomada: o gancho reconhece e não troca o pedido.
MARCA = "[continuidade]"
# Presente no ambiente do `claude -p` que o verificador dispara.
ENV_ORIGEM = "ROTEADOR_CONTINUIDADE_ORIGEM"

PADRAO = {
    "intervalo_min": 15,  # período do timer; base do backoff sem horário de reset
    "margem_reset_min": 3,  # folga depois do reset informado
    "carencia_nativa_min": 20,  # sessão interativa viva: espera o auto-continue nativo
    "max_tentativas": 6,
    "teto_horas": 30,  # desde a primeira detecção; reset além disso = desiste
    "backoff_max_min": 240,
    "timeout_retomada_min": 240,
    "erros_retomaveis": ["rate_limit", "server_error"],
    "permissao": None,  # ex.: "bypassPermissions"; None = modo padrão do settings
    "claude_bin": None,
    "notificar_cmd": None,  # lista; recebe a mensagem no stdin
}

SITUACOES_FINAIS = {
    "concluida",
    "continuada",
    "abandonada",
    "retomada_por_outro",
    "retomada_nativa",
    "assumida",
    "falha",
}


# ------------------------------------------------------------ utilidades
def agora() -> datetime:
    return datetime.now(timezone.utc)


def iso(dt: datetime | None) -> str | None:
    return dt.astimezone(timezone.utc).isoformat(timespec="seconds") if dt else None


def de_iso(texto: str | None) -> datetime | None:
    if not texto:
        return None
    try:
        # O transcript grava "...000Z"; o fromisoformat do Python < 3.11 não aceita o "Z".
        dt = datetime.fromisoformat(texto[:-1] + "+00:00" if texto.endswith("Z") else texto)
    except (ValueError, TypeError):
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def hora_local(dt: datetime | None) -> str:
    return dt.astimezone().strftime("%d/%m %H:%M") if dt else "?"


def curto(sid: str | None) -> str:
    return (sid or "?")[:8]


def resumo(texto: str, limite: int = 400) -> str:
    texto = re.sub(r"\s+", " ", mascarar(texto or "")).strip()
    return texto if len(texto) <= limite else texto[: limite - 1] + "…"


def carregar_config() -> dict:
    cfg = dict(PADRAO)
    try:
        cfg.update(json.loads(ARQ_CONFIG_LOCAL.read_text(encoding="utf-8")))
    except (OSError, ValueError):
        pass
    if os.getenv("ROTEADOR_CONTINUIDADE_PERMISSAO"):
        cfg["permissao"] = os.environ["ROTEADOR_CONTINUIDADE_PERMISSAO"]
    if os.getenv("ROTEADOR_CONTINUIDADE_CLAUDE"):
        cfg["claude_bin"] = os.environ["ROTEADOR_CONTINUIDADE_CLAUDE"]
    return cfg


def escrever(texto: str) -> None:
    """Saída do modo CLI; sob `pyw` (Windows, sem console) não há stdout."""
    if sys.stdout is not None:
        try:
            sys.stdout.write(texto + "\n")
            sys.stdout.flush()
        except (OSError, ValueError):
            pass


def processo_vivo(pid: int) -> bool:
    if pid <= 0:
        return False
    if os.name == "nt":
        # os.kill(pid, 0) no Windows ENCERRA o processo; consulta pela API.
        import ctypes

        kernel32 = ctypes.windll.kernel32
        handle = kernel32.OpenProcess(0x1000, False, pid)  # QUERY_LIMITED_INFORMATION
        if not handle:
            return False
        try:
            codigo = ctypes.c_ulong()
            ok = kernel32.GetExitCodeProcess(handle, ctypes.byref(codigo))
            return bool(ok) and codigo.value == 259  # STILL_ACTIVE
        finally:
            kernel32.CloseHandle(handle)
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


# --------------------------------------------------------------- travas
def _tentar_travar(fd: int) -> bool:
    try:
        if os.name == "nt":
            import msvcrt

            os.lseek(fd, 0, os.SEEK_SET)
            msvcrt.locking(fd, msvcrt.LK_NBLCK, 1)
        else:
            import fcntl

            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return True
    except OSError:
        return False


def _destravar(fd: int) -> None:
    try:
        if os.name == "nt":
            import msvcrt

            os.lseek(fd, 0, os.SEEK_SET)
            msvcrt.locking(fd, msvcrt.LK_UNLCK, 1)
        else:
            import fcntl

            fcntl.flock(fd, fcntl.LOCK_UN)
    except OSError:
        pass


@contextmanager
def trava(caminho: Path, espera_s: float):
    """Trava do sistema operacional (flock/msvcrt) sobre um arquivo fixo.

    O SO solta a trava quando o processo morre, então não há trava "velha" a
    adivinhar nem corrida ao apagá-la; o arquivo nunca é removido.
    """
    DIR_ESTADO.mkdir(parents=True, exist_ok=True)
    fd = os.open(caminho, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        limite = time.monotonic() + espera_s
        while not _tentar_travar(fd):
            if time.monotonic() >= limite:
                raise TimeoutError(str(caminho))
            time.sleep(0.05)
        try:
            yield
        finally:
            _destravar(fd)
    finally:
        os.close(fd)


# --------------------------------------------------------------- estado
def ler_estado() -> dict:
    try:
        estado = json.loads(ARQ_ESTADO.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        estado = {}
    estado.setdefault("versao", 1)
    estado.setdefault("sessoes", {})
    estado.setdefault("avisos", [])
    return estado


def gravar_estado(estado: dict) -> None:
    DIR_ESTADO.mkdir(parents=True, exist_ok=True)
    tmp = ARQ_ESTADO.with_name(f"estado.{os.getpid()}.tmp")
    tmp.write_text(json.dumps(estado, ensure_ascii=False, indent=1), encoding="utf-8")
    for tentativa in range(20):
        try:
            os.replace(tmp, ARQ_ESTADO)
            return
        except PermissionError:  # Windows: leitor com o arquivo aberto
            time.sleep(0.05 * (tentativa + 1))
    os.replace(tmp, ARQ_ESTADO)


@contextmanager
def estado_travado(gravar: bool = True):
    """Lê o estado sob a trava; grava ao sair (`gravar=False` no modo seco: só leitura)."""
    with trava(TRAVA_ESTADO, espera_s=5):
        estado = ler_estado()
        yield estado
        if gravar:
            podar(estado)
            gravar_estado(estado)
            gravar_status_linha(estado)
    # Notificação externa só depois de soltar a trava: um comando lento não pode
    # segurar os ganchos das outras sessões nem estourar o timeout deste gancho.
    _enviar_notificacoes()


def podar(estado: dict) -> None:
    limite_final = agora() - timedelta(days=7)
    limite_aberta = agora() - timedelta(days=30)
    for sid, s in list(estado["sessoes"].items()):
        atualizado = de_iso(s.get("atualizado_em")) or agora()
        if (s.get("situacao") in SITUACOES_FINAIS and atualizado < limite_final) or (
            atualizado < limite_aberta
        ):
            del estado["sessoes"][sid]
        else:
            s["historico"] = s.get("historico", [])[-10:]
    estado["avisos"] = estado["avisos"][-30:]


def registrar_log(evento: str, **dados) -> None:
    DIR_ESTADO.mkdir(parents=True, exist_ok=True)
    try:
        if ARQ_LOG.exists() and ARQ_LOG.stat().st_size > 1_000_000:
            os.replace(ARQ_LOG, ARQ_LOG.with_name("log.1.jsonl"))
    except OSError:
        pass
    linha = {"em": iso(agora()), "maquina": MACHINE_PREFIX, "evento": evento} | dados
    with ARQ_LOG.open("a", encoding="utf-8") as arq:
        arq.write(json.dumps(linha, ensure_ascii=False) + "\n")


def avisar(estado: dict, cfg: dict, cwd: str | None, texto: str, *, externo: bool = True) -> None:
    """Sinal de vida: aviso para a próxima mensagem do coordenador, log e notificação."""
    estado["avisos"].append({"em": iso(agora()), "cwd": _norm(cwd), "texto": texto, "entregue": False})
    registrar_log("aviso", texto=texto)
    if externo:
        _NOTIFICACOES.append((cfg, texto))


# Fila esvaziada por `estado_travado` depois de soltar a trava.
_NOTIFICACOES: list[tuple[dict, str]] = []


def _enviar_notificacoes() -> None:
    while _NOTIFICACOES:
        cfg, texto = _NOTIFICACOES.pop(0)
        notificar(cfg, texto)


def notificar(cfg: dict, texto: str) -> None:
    mensagem = f"[{MACHINE_PREFIX}] continuidade: {texto}"
    if sys.stderr is not None:  # no VPS vai para o journal do serviço
        try:
            sys.stderr.write(mensagem + "\n")
        except (OSError, ValueError):
            pass
    comando = cfg.get("notificar_cmd")
    if not comando:
        return
    try:
        subprocess.run(
            comando,
            input=mensagem.encode("utf-8"),
            timeout=5,  # abaixo do timeout de 10 s do gancho
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            **_sem_janela(),
        )
    except (OSError, subprocess.SubprocessError) as exc:
        registrar_log("notificacao_falhou", erro=type(exc).__name__)


def _norm(cwd: str | None) -> str | None:
    return os.path.normcase(os.path.normpath(cwd)) if cwd else None


def _sem_janela() -> dict:
    if os.name == "nt":
        return {"creationflags": getattr(subprocess, "CREATE_NO_WINDOW", 0x08000000)}
    return {}


def gravar_status_linha(estado: dict) -> None:
    """Linha extra da statusline: só aparece quando há algo a esperar."""
    esperando = [s for s in estado["sessoes"].values() if s.get("situacao") in ("limite", "retomando")]
    if not esperando:
        texto = ""
    else:
        proxima = min(
            (
                de_iso(s.get("proxima_verificacao")) or agora()
                for s in esperando
                if s.get("situacao") == "limite"
            ),
            default=None,
        )
        rodando = sum(1 for s in esperando if s.get("situacao") == "retomando")
        partes = [f"continuidade: {len(esperando)} sessão(ões) parada(s) por limite"]
        if proxima:
            partes.append(f"retoma ~{hora_local(proxima)}")
        if rodando:
            partes.append(f"{rodando} retomando agora")
        texto = " · ".join(partes) + "\n"
    try:
        ARQ_STATUS.write_text(texto, encoding="utf-8")
    except OSError:
        pass


# ------------------------------------------------------- horário de reset
_DIAS = {"mon": 0, "tue": 1, "wed": 2, "thu": 3, "fri": 4, "sat": 5, "sun": 6}
_RE_RESET = re.compile(
    r"resets?\s+(?:at\s+)?(?:(mon|tue|wed|thu|fri|sat|sun)\w*\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)"
    r"(?:\s*\(([^)]+)\))?",
    re.I,
)


def _cauda(caminho: str | None, bytes_max: int = 256_000) -> list[str]:
    """Últimas linhas do transcript JSONL (a primeira pode vir cortada; é ignorada no parse)."""
    if not caminho:
        return []
    try:
        with open(caminho, "rb") as arq:
            arq.seek(0, os.SEEK_END)
            arq.seek(max(0, arq.tell() - bytes_max))
            return arq.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return []


def transcript_avancou(caminho: str | None, desde: datetime) -> bool:
    """Há mensagem de conversa (não erro de API) depois de `desde`? Metadados não contam."""
    for linha in reversed(_cauda(caminho)):
        try:
            dado = json.loads(linha)
        except ValueError:
            continue
        if not isinstance(dado, dict) or dado.get("type") not in ("user", "assistant"):
            continue
        quando = de_iso(dado.get("timestamp"))
        if not quando:
            continue
        if quando <= desde:
            return False
        if not dado.get("isApiErrorMessage"):
            return True
    return False


def _de_epoch(valor) -> datetime | None:
    if not isinstance(valor, (int, float)) or isinstance(valor, bool) or valor <= 0:
        return None
    if valor > 1e11:  # milissegundos
        valor /= 1000
    try:
        return datetime.fromtimestamp(valor, timezone.utc)
    except (OverflowError, ValueError, OSError):
        return None


def reset_do_transcript(caminho: str | None) -> tuple[datetime | None, str | None]:
    """Último erro de API no transcript (`resetsAt` em epoch; formato interno, best-effort).

    Só vale o erro desta parada: linha de erro com mais de 10 min é de um limite antigo.
    """
    for linha in reversed(_cauda(caminho)):
        if '"isApiErrorMessage":true' not in linha.replace(" ", ""):
            continue
        try:
            dado = json.loads(linha)
        except ValueError:
            continue
        if not isinstance(dado, dict):
            continue
        quando = de_iso(dado.get("timestamp"))
        if quando and agora() - quando > timedelta(minutes=10):
            return None, None
        params = dado.get("apiErrorParams") if isinstance(dado.get("apiErrorParams"), dict) else {}
        info = params.get("rate_limit_info") or dado.get("quotaLimits") or {}
        if not isinstance(info, dict):
            info = {}
        tipo = info.get("rateLimitType")
        reset = _de_epoch(info.get("resetsAt"))
        if reset:
            return reset, tipo
        texto = " ".join(
            c.get("text", "") for c in (dado.get("message") or {}).get("content") or [] if isinstance(c, dict)
        )
        return reset_do_texto(texto, de_iso(dado.get("timestamp")) or agora()), tipo
    return None, None


def reset_do_texto(texto: str | None, referencia: datetime) -> datetime | None:
    """Interpreta "resets 3:45pm", "resets Mon 12:00am", "resets 2:50am (America/Sao_Paulo)"."""
    m = _RE_RESET.search(texto or "")
    if not m:
        return None
    dia, hora, minuto, ampm, nome_tz = m.groups()
    hora = int(hora) % 12 + (12 if ampm.lower() == "pm" else 0)
    minuto = int(minuto or 0)
    fuso = None
    if nome_tz:
        try:
            from zoneinfo import ZoneInfo

            fuso = ZoneInfo(nome_tz.strip())
        except Exception:  # noqa: BLE001 - sem tzdata (Windows) usa o fuso local
            fuso = None
    base = referencia.astimezone(fuso) if fuso else referencia.astimezone()
    alvo = base.replace(hour=hora, minute=minuto, second=0, microsecond=0)
    if dia:
        alvo += timedelta(days=(_DIAS[dia.lower()[:3]] - alvo.weekday()) % 7)
    while alvo <= base:
        alvo += timedelta(days=7 if dia else 1)
    return alvo.astimezone(timezone.utc)


def calcular_proxima(s: dict, cfg: dict) -> datetime:
    reset = de_iso((s.get("limite") or {}).get("reset_em"))
    if reset:
        return max(reset + timedelta(minutes=cfg["margem_reset_min"]), agora() + timedelta(minutes=1))
    espera = min(cfg["intervalo_min"] * (2 ** s.get("tentativas", 0)), cfg["backoff_max_min"])
    return agora() + timedelta(minutes=espera)


# ------------------------------------------------------------ ganchos
def nova_sessao(sid: str) -> dict:
    return {"sid": sid, "situacao": "em_andamento", "tentativas": 0, "historico": []}


def registrar_limite(estado: dict, s: dict, cfg: dict, erro: str, texto: str | None) -> None:
    detectado = agora()
    reset, tipo = reset_do_transcript(s.get("transcript"))
    fonte = "transcript" if reset else None
    if not reset and texto:
        reset = reset_do_texto(texto, detectado)
        fonte = "texto" if reset else None
    s["situacao"] = "limite"
    s["limite"] = {
        "erro": erro,
        "tipo": tipo,
        "detectado_em": iso(detectado),
        "reset_em": iso(reset),
        "fonte_reset": fonte,
    }
    s.setdefault("primeira_deteccao", None)
    s["primeira_deteccao"] = s["primeira_deteccao"] or iso(detectado)
    s["carencia_aplicada"] = False
    s["proxima_verificacao"] = iso(calcular_proxima(s, cfg))
    s["historico"].append({"em": iso(detectado), "evento": "limite", "erro": erro, "reset_em": iso(reset)})
    previsao = hora_local(de_iso(s["proxima_verificacao"]))
    avisar(
        estado,
        cfg,
        _proj(s),
        f"sessão {curto(s['sid'])} parou por {erro} às {hora_local(detectado)}"
        + (f" (reset {hora_local(reset)})" if reset else " (reset não informado)")
        + f"; retomada automática prevista para ~{previsao}. Pedido: {s.get('pedido') or '?'}",
    )


def avisos_pendentes(estado: dict, cfg: dict, cwd: str | None) -> str:
    alvo = _norm(cwd)
    linhas = []
    for aviso in estado["avisos"]:
        if not aviso.get("entregue") and (aviso.get("cwd") in (None, alvo)):
            linhas.append(f"- {hora_local(de_iso(aviso.get('em')))}: {aviso['texto']}")
            aviso["entregue"] = True
    esperando = [
        s
        for s in estado["sessoes"].values()
        if s.get("situacao") == "limite" and _norm(s.get("cwd_projeto") or s.get("cwd")) == alvo
    ]
    ultima = de_iso(estado.get("ultima_verificacao"))
    ja_avisou = de_iso(estado.get("alerta_agendador_em"))
    if (
        esperando
        and (not ultima or agora() - ultima > timedelta(minutes=3 * cfg["intervalo_min"]))
        and (not ja_avisou or agora() - ja_avisou > timedelta(hours=1))
    ):
        estado["alerta_agendador_em"] = iso(agora())
        linhas.append(
            "- ATENÇÃO: há sessão parada por limite e o agendador da continuidade não roda desde "
            f"{hora_local(ultima) if ultima else 'nunca'}; confira o timer (ver tooling.md)."
        )
    if not linhas:
        return ""
    return "[continuidade] Eventos de limite/retomada automática desde a última mensagem:\n" + "\n".join(
        linhas
    )


def ao_evento(entrada: dict) -> str:
    evento = entrada.get("hook_event_name") or ""
    sid = entrada.get("session_id")
    if not sid:
        return ""
    cfg = carregar_config()
    origem = os.getenv(ENV_ORIGEM)
    contexto = ""
    with estado_travado() as estado:
        sessoes = estado["sessoes"]
        s = sessoes.get(sid)
        if s is None:
            s = nova_sessao(sid)
            pai = sessoes.get(origem) if origem and origem != sid else None
            if pai:  # sessão nova criada pela retomada com --fork-session
                for chave in ("pedido", "pedido_em", "primeira_deteccao", "tentativas"):
                    s[chave] = pai.get(chave)
                s["tentativas"] = s.get("tentativas") or 0
                s["cwd_projeto"] = pai.get("cwd_projeto") or pai.get("cwd")
                s["origem"] = origem
                s["situacao"] = "retomando"
                s["retomada_iniciada_em"] = iso(agora())
            sessoes[sid] = s
        s["cwd"] = entrada.get("cwd") or s.get("cwd")
        # Pasta em que a sessão nasceu: o `--resume` procura a sessão pelo projeto
        # dessa pasta, não pela atual (worktree/subpasta para onde ela tenha ido).
        s["cwd_projeto"] = s.get("cwd_projeto") or s["cwd"]
        s["transcript"] = entrada.get("transcript_path") or s.get("transcript")
        s["atualizado_em"] = iso(agora())

        if evento == "UserPromptSubmit":
            prompt = entrada.get("prompt") or ""
            if prompt.lstrip().startswith(MARCA):
                s["situacao"] = "retomando"
            else:
                s.update(situacao="em_andamento", tentativas=0, limite=None, primeira_deteccao=None)
                # "ok", "continue", "sim": não apagam o pedido que descreve a tarefa.
                if len(prompt.strip()) >= 20 or not s.get("pedido"):
                    s.update(pedido=resumo(prompt), pedido_em=iso(agora()))
            if not origem:
                contexto = avisos_pendentes(estado, cfg, _proj(s))
        elif evento == "SessionStart":
            if entrada.get("source") == "resume" and not origem and s.get("situacao") == "limite":
                # O usuário retomou a sessão à mão: ele assume, o agendador não mexe.
                s["situacao"] = "assumida"
                s["historico"].append({"em": iso(agora()), "evento": "assumida"})
                registrar_log("assumida", sessao=curto(sid))
            if not origem:
                contexto = avisos_pendentes(estado, cfg, _proj(s))
        elif evento == "Stop":
            if s.get("situacao") in ("em_andamento", "retomando"):
                s["situacao"] = "concluida"
        elif evento == "StopFailure":
            erro = entrada.get("error") or "unknown"
            texto = " ".join(str(entrada.get(c) or "") for c in ("last_assistant_message", "error_details"))
            if erro in cfg["erros_retomaveis"]:
                registrar_limite(estado, s, cfg, erro, texto)
            else:
                s["situacao"] = "falha"
                s["historico"].append({"em": iso(agora()), "evento": "falha", "erro": erro})
                registrar_log("falha_nao_retomavel", sessao=curto(sid), erro=erro)
        elif evento == "Notification":
            if (
                entrada.get("notification_type") == "quota_auto_resume_fired"
                and s.get("situacao") == "limite"
            ):
                s["situacao"] = "retomada_nativa"
                s["historico"].append({"em": iso(agora()), "evento": "retomada_nativa"})
                registrar_log("retomada_nativa", sessao=curto(sid))
    return contexto


# ---------------------------------------------------------- verificador
def sessao_viva(sid: str) -> dict | None:
    """Registro do processo que segura a sessão (`~/.claude/sessions/<pid>.json`), se vivo."""
    try:
        arquivos = list(DIR_SESSOES.glob("*.json"))
    except OSError:
        return None
    for arq in arquivos:
        try:
            dado = json.loads(arq.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if dado.get("sessionId") == sid and processo_vivo(int(dado.get("pid") or 0)):
            return dado
    return None


def instrucao(s: dict, cfg: dict) -> str:
    limite = s.get("limite") or {}
    return (
        f"{MARCA} Retomada automática: esta sessão parou por {limite.get('erro', 'limite')} em "
        f"{hora_local(de_iso(limite.get('detectado_em')))} e o horário de retomada chegou "
        f"(tentativa {s.get('tentativas', 0)} de {cfg['max_tentativas']}). Continue a tarefa pendente "
        "de onde parou, sem refazer o que já foi concluído. Último pedido do usuário: "
        f'"{s.get("pedido") or "não registrado; use o histórico desta conversa"}". Antes de agir, confira o '
        "estado real (git status, arquivos, tarefas e subagentes); subagentes parados por limite "
        "devem ser retomados com SendMessage. Ao terminar, entregue o relatório final normalmente."
    )


def _proj(s: dict) -> str | None:
    return s.get("cwd_projeto") or s.get("cwd")


def localizar_claude(cfg: dict) -> str | None:
    if cfg.get("claude_bin"):
        return cfg["claude_bin"]
    if os.name == "nt":
        # Só o executável nativo: um `claude.cmd` (npm) passaria a instrução, que
        # contém o pedido do usuário, pelo cmd.exe, que reinterpreta & | % ^ e aspas.
        candidatos = [shutil.which("claude.exe"), str(Path.home() / ".local" / "bin" / "claude.exe")]
    else:
        candidatos = [shutil.which("claude"), str(Path.home() / ".local" / "bin" / "claude")]
    for candidato in candidatos:
        if candidato and Path(candidato).is_file():
            return candidato
    return None


def executar_retomada(sid: str, s: dict, cfg: dict, fork: bool) -> dict:
    claude = localizar_claude(cfg)
    if not claude:
        return {"ok": False, "motivo": "claude_nao_encontrado"}
    if os.name == "nt" and Path(claude).suffix.lower() in (".cmd", ".bat"):
        return {"ok": False, "motivo": "claude_cmd_nao_suportado"}
    comando = [claude, "-p", "--resume", sid, "--output-format", "json"]
    if fork:
        comando.append("--fork-session")
    if cfg.get("permissao"):
        comando += ["--permission-mode", cfg["permissao"]]
    comando.append(instrucao(s, cfg))
    ambiente = dict(os.environ)
    ambiente[ENV_ORIGEM] = sid
    try:
        proc = subprocess.run(
            comando,
            cwd=_proj(s),
            env=ambiente,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            timeout=cfg["timeout_retomada_min"] * 60,
            check=False,
            **_sem_janela(),
        )
    except subprocess.TimeoutExpired:
        return {"ok": False, "motivo": "timeout"}
    except OSError as exc:
        return {"ok": False, "motivo": f"erro_ao_iniciar:{type(exc).__name__}"}
    saida = proc.stdout.decode("utf-8", "replace").strip()
    dado: dict = {}
    for linha in reversed(saida.splitlines()):
        try:
            dado = json.loads(linha)
            break
        except ValueError:
            continue
    texto = str(dado.get("result") or "") or proc.stderr.decode("utf-8", "replace")[-2000:]
    ok = proc.returncode == 0 and bool(dado) and not dado.get("is_error")
    return {
        "ok": ok,
        "codigo": proc.returncode,
        "subtype": dado.get("subtype"),
        "sessao": dado.get("session_id"),
        "texto": texto,
        "limite": not ok
        and bool(re.search(r"\b(?:limit|rate.?limit|429|quota|overloaded|529)\b", texto, re.I)),
    }


def verificar(seco: bool = False) -> int:
    cfg = carregar_config()
    try:
        with trava(TRAVA_VERIFICACAO, espera_s=0):
            return _verificar(cfg, seco)
    except TimeoutError:
        escrever("continuidade: outra verificação em andamento; nada a fazer.")
        return 0


def _verificar(cfg: dict, seco: bool) -> int:
    with estado_travado(gravar=not seco) as estado:
        if not seco:
            estado["ultima_verificacao"] = iso(agora())
        vencidas = [
            sid
            for sid, s in estado["sessoes"].items()
            if s.get("situacao") == "limite" and (de_iso(s.get("proxima_verificacao")) or agora()) <= agora()
        ]
        # Sessão que ficou em "retomando" sem processo vivo (verificador morto no meio).
        for sid, s in estado["sessoes"].items():
            inicio = de_iso(s.get("retomada_iniciada_em"))
            if (
                s.get("situacao") == "retomando"
                and inicio
                and agora() - inicio > timedelta(minutes=cfg["timeout_retomada_min"] + 30)
            ):
                s["situacao"] = "limite"
                s["proxima_verificacao"] = iso(agora())
                vencidas.append(sid)
    if not vencidas:
        escrever("continuidade: nenhuma sessão vencida.")
    for sid in vencidas:
        _tratar(sid, cfg, seco)
    return 0


def _tratar(sid: str, cfg: dict, seco: bool) -> None:
    with estado_travado(gravar=not seco) as estado:
        s = estado["sessoes"].get(sid)
        if not s or s.get("situacao") != "limite":
            return
        s.setdefault("historico", [])
        limite = s.get("limite") or {}
        detectado = de_iso(limite.get("detectado_em")) or agora()
        primeira = de_iso(s.get("primeira_deteccao")) or detectado
        reset = de_iso(limite.get("reset_em"))
        teto = primeira + timedelta(hours=cfg["teto_horas"])
        motivo = None
        if s.get("tentativas", 0) >= cfg["max_tentativas"]:
            motivo = f"{s['tentativas']} tentativas sem sucesso"
        elif agora() > teto or (reset and reset > teto):
            motivo = f"limite além do teto de {cfg['teto_horas']}h" + (
                f" (reset {hora_local(reset)})" if reset else ""
            )
        elif not _proj(s) or not Path(_proj(s)).is_dir():
            motivo = "diretório da sessão não existe mais"
        if motivo:
            escrever(f"continuidade: {curto(sid)} -> abandonar ({motivo})")
            if not seco:
                s["situacao"] = "abandonada"
                s["historico"].append({"em": iso(agora()), "evento": "abandonada", "motivo": motivo})
                avisar(
                    estado,
                    cfg,
                    _proj(s),
                    f"desisti de retomar a sessão {curto(sid)}: {motivo}. Retome à mão "
                    f"(`claude --resume {sid}`). Pedido: {s.get('pedido') or '?'}",
                )
            return
        # Alguém já continuou (usuário, auto-continue nativo): há conversa nova no transcript.
        if transcript_avancou(s.get("transcript"), detectado + timedelta(minutes=2)):
            escrever(f"continuidade: {curto(sid)} -> já continuada por outro meio")
            if not seco:
                s["situacao"] = "retomada_por_outro"
                s["historico"].append({"em": iso(agora()), "evento": "retomada_por_outro"})
                registrar_log("retomada_por_outro", sessao=curto(sid))
            return
        viva = sessao_viva(sid)
        # `cli`/desktop têm o auto-continue nativo; `sdk-*` (Remote Control, -p) não.
        interativa = bool(viva) and not str(viva.get("entrypoint") or "").startswith("sdk")
        if interativa and not s.get("carencia_aplicada"):
            # Sessão aberta no terminal: dá a vez ao auto-continue nativo antes do fork.
            escrever(f"continuidade: {curto(sid)} -> sessão interativa viva; carência")
            if not seco:
                s["carencia_aplicada"] = True
                s["proxima_verificacao"] = iso(agora() + timedelta(minutes=cfg["carencia_nativa_min"]))
            return
        fork = bool(viva)
        escrever(f"continuidade: {curto(sid)} -> retomar ({'fork' if fork else 'no lugar'})")
        if seco:
            return
        s["situacao"] = "retomando"
        s["tentativas"] = s.get("tentativas", 0) + 1
        s["retomada_iniciada_em"] = iso(agora())
        s["historico"].append({"em": iso(agora()), "evento": "retomando", "fork": fork})
        avisar(
            estado,
            cfg,
            _proj(s),
            f"retomada automática da sessão {curto(sid)} iniciada "
            f"({'em sessão nova, a original segue aberta' if fork else 'na própria sessão'}; "
            f"tentativa {s['tentativas']}/{cfg['max_tentativas']}).",
        )
        copia = dict(s)

    resultado = executar_retomada(sid, copia, cfg, fork)

    with estado_travado() as estado:
        s = estado["sessoes"].get(sid) or copia
        estado["sessoes"][sid] = s
        destino_sid = resultado.get("sessao")
        destino = estado["sessoes"].get(destino_sid) if destino_sid and destino_sid != sid else None
        texto = resumo(resultado.get("texto") or "", 300)
        s["historico"].append(
            {
                "em": iso(agora()),
                "evento": "retomada_ok" if resultado["ok"] else "retomada_falhou",
                "codigo": resultado.get("codigo"),
                "subtype": resultado.get("subtype"),
                "motivo": resultado.get("motivo"),
                "sessao": curto(destino_sid),
            }
        )
        registrar_log(
            "retomada",
            sessao=curto(sid),
            ok=resultado["ok"],
            codigo=resultado.get("codigo"),
            subtype=resultado.get("subtype"),
            motivo=resultado.get("motivo"),
            limite=resultado.get("limite"),
            destino=curto(destino_sid),
        )
        # Só limite de novo (ou timeout) volta para a fila; outra falha (binário
        # ausente, sessão não encontrada, autenticação) para e mostra o motivo real.
        retomavel = bool(resultado.get("limite")) or resultado.get("motivo") == "timeout"
        if destino is not None:
            # Fork: a sessão nova carrega a tarefa (os ganchos dela já registraram).
            s["situacao"] = "continuada"
            s["continuada_em"] = destino_sid
            if not resultado["ok"] and destino.get("situacao") in ("retomando", "em_andamento"):
                _apos_falha(destino, cfg, texto, retomavel)
        elif not resultado["ok"] and s.get("situacao") in ("retomando", "em_andamento", "concluida"):
            _apos_falha(s, cfg, texto, retomavel)
        elif resultado["ok"] and s.get("situacao") == "retomando":
            s["situacao"] = "concluida"
        alvo = destino or s
        if resultado["ok"]:
            msg = f"retomada automática da sessão {curto(sid)} terminou às {hora_local(agora())}"
            if destino is not None:
                msg += f" na sessão {destino_sid} (`claude --resume {destino_sid}` para ver)"
            msg += f". Resumo: {texto or '(sem texto)'}"
        elif alvo.get("situacao") == "limite":
            msg = (
                f"retomada da sessão {curto(sid)} esbarrou no limite de novo; próxima tentativa "
                f"~{hora_local(de_iso(alvo.get('proxima_verificacao')))}."
            )
        else:
            causa = resultado.get("motivo") or resultado.get("subtype") or f"código {resultado.get('codigo')}"
            msg = (
                f"retomada da sessão {curto(sid)} falhou ({causa}): {texto}. Sem nova tentativa "
                f"automática; retome à mão (`claude --resume {sid}`)."
            )
        avisar(estado, cfg, _proj(s), msg)


def _apos_falha(s: dict, cfg: dict, texto: str, retomavel: bool) -> None:
    if retomavel:
        _voltar_para_limite(s, cfg, texto)
    else:
        s["situacao"] = "falha"
        s["historico"].append({"em": iso(agora()), "evento": "falha", "erro": "retomada"})


def _voltar_para_limite(s: dict, cfg: dict, texto: str) -> None:
    s["situacao"] = "limite"
    limite = s.get("limite") or {}
    novo_reset = reset_do_texto(texto, agora())
    limite.update(
        detectado_em=iso(agora()), reset_em=iso(novo_reset), fonte_reset="texto" if novo_reset else None
    )
    s["limite"] = limite
    s["proxima_verificacao"] = iso(calcular_proxima(s, cfg))


# ------------------------------------------------------------ instalação
EVENTOS_GANCHO = ("UserPromptSubmit", "SessionStart", "Stop", "StopFailure", "Notification")


def registrar_hooks(arquivo: Path) -> int:
    """Acrescenta os ganchos ao settings.json indicado (idempotente, com backup)."""
    script = str(Path(__file__).resolve())
    if os.name == "nt":
        script = script.replace("\\", "/")
        gancho = {"type": "command", "command": "py", "args": ["-3", script], "timeout": 10}
    else:
        gancho = {"type": "command", "command": "python3", "args": [script], "timeout": 10}
    dados = json.loads(arquivo.read_text(encoding="utf-8")) if arquivo.exists() else {}
    hooks = dados.setdefault("hooks", {})
    novos = []
    for evento in EVENTOS_GANCHO:
        grupos = hooks.setdefault(evento, [])
        ja = any("continuidade.py" in json.dumps(h) for g in grupos for h in g.get("hooks", []))
        if not ja:
            grupo = {"hooks": [dict(gancho)]}
            if evento == "Notification":
                grupo["matcher"] = "quota_auto_resume_fired"
            grupos.append(grupo)
            novos.append(evento)
    if not novos:
        escrever(f"ganchos já registrados em {arquivo}")
        return 0
    if arquivo.exists():
        copia = arquivo.with_name(f"{arquivo.name}.bak-continuidade-{datetime.now():%Y%m%d%H%M%S}")
        shutil.copy2(arquivo, copia)
        escrever(f"backup: {copia}")
    arquivo.write_text(json.dumps(dados, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    escrever(f"ganchos registrados em {arquivo}: {', '.join(novos)}")
    return 0


def mostrar_status() -> int:
    cfg = carregar_config()
    estado = ler_estado()
    escrever(f"máquina: {MACHINE_PREFIX} · estado: {ARQ_ESTADO}")
    escrever(f"última verificação do agendador: {hora_local(de_iso(estado.get('ultima_verificacao')))}")
    escrever(
        f"claude: {localizar_claude(cfg) or 'NÃO ENCONTRADO'} · permissão: {cfg.get('permissao') or 'padrão'}"
    )
    for sid, s in estado["sessoes"].items():
        if s.get("situacao") in ("em_andamento", "concluida"):
            continue
        escrever(
            f"- {curto(sid)} {s.get('situacao')} tentativas={s.get('tentativas', 0)} "
            f"próxima={hora_local(de_iso(s.get('proxima_verificacao')))} cwd={s.get('cwd')}"
        )
    pendentes = sum(1 for a in estado["avisos"] if not a.get("entregue"))
    escrever(f"avisos não entregues: {pendentes}")
    return 0


def main() -> int:
    args = sys.argv[1:]
    if args:
        if sys.stdout is not None and hasattr(sys.stdout, "reconfigure"):
            sys.stdout.reconfigure(encoding="utf-8")
        if args[0] == "--verificar":
            try:
                return verificar(seco="--seco" in args)
            except Exception as exc:  # noqa: BLE001 - registra e sai; o timer tenta de novo
                registrar_log("erro_verificador", erro=f"{type(exc).__name__}: {resumo(str(exc), 200)}")
                return 1
        if args[0] == "--status":
            return mostrar_status()
        if args[0] == "--registrar-hooks" and len(args) > 1:
            return registrar_hooks(Path(args[1]))
        escrever("uso: continuidade.py [--verificar [--seco] | --status | --registrar-hooks <settings.json>]")
        return 2
    # Gancho: nunca pode travar nem derrubar a sessão.
    try:
        entrada = json.loads(sys.stdin.buffer.read().decode("utf-8", "replace") or "{}")
        contexto = ao_evento(entrada)
        evento = entrada.get("hook_event_name")
        if contexto and evento in ("UserPromptSubmit", "SessionStart"):
            saida = {"hookSpecificOutput": {"hookEventName": evento, "additionalContext": contexto}}
            sys.stdout.buffer.write(json.dumps(saida, ensure_ascii=False).encode("utf-8"))
    except Exception as exc:  # noqa: BLE001
        try:
            registrar_log("erro_gancho", erro=type(exc).__name__)
        except Exception:  # noqa: BLE001
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
