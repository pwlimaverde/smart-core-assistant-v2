"""Roteador de modelo + seletor de skill (gancho UserPromptSubmit).

Contrato (documentado em `.context/docs/tooling.md`, para permitir portar):
- stdin: JSON do Claude Code (`prompt`, `session_id`, ...).
- stdout: JSON `hookSpecificOutput.additionalContext` ou nada.
- Efeitos: uma linha em `.claude/roteador/decisoes.jsonl` e o texto pronto da
  linha de status em `.claude/roteador/status.txt`.

Uma única chamada ao Jev por mensagem decide nível, especialista, skill,
risco, continuação e se o entregável é texto. A política fica no código
(`decidir`), com limiares em `.claude/roteador.config.json`.

Modos (`.claude/roteador/modo`): `on` (delegação + skill), `skills` (só a
skill) e `off`. Sem o arquivo, vale `modo_padrao` da configuração.

Uso fora do gancho: `roteador.py --cli on|skills|off|status`.
"""

from __future__ import annotations

import json
import os
import re
import socket
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

_INICIO = time.perf_counter()

# Caminhos resolvidos a partir do script, nunca do CWD.
CLAUDE_DIR = Path(__file__).resolve().parent.parent
RAIZ = CLAUDE_DIR.parent  # smart-agent-config/
DIR_ESTADO = CLAUDE_DIR / "roteador"
ARQ_CONFIG = CLAUDE_DIR / "roteador.config.json"
ARQ_MODO = DIR_ESTADO / "modo"
ARQ_LOG = DIR_ESTADO / "decisoes.jsonl"
ARQ_STATUS = DIR_ESTADO / "status.txt"
ARQ_CATALOGO = DIR_ESTADO / "catalogo.json"
DIR_SKILLS = RAIZ / ".context" / "skills"
DIR_AGENTES = RAIZ / ".context" / "agents"
ARQ_WORKFLOW = RAIZ / ".context" / "workflow" / "status.yaml"
MODOS = ("on", "skills", "off")

# Máquina que escreve o status: o mesmo repositório roda no PC e no VPS, e o
# prefixo deixa claro de onde veio cada linha. ROTEADOR_MACHINE tem precedência
# (o hostname do VPS Hostinger, srv1321059, não contém "vps").
MACHINE_PREFIX = os.getenv("ROTEADOR_MACHINE") or (
    "VPS" if "vps" in socket.gethostname().lower() else "LOCAL"
)
# Largura fixa para LOCAL e VPS alinharem na linha de status.
_ROTULO_MAQUINA = f"[{MACHINE_PREFIX.upper()}]".ljust(8)


# ------------------------------------------------------------ utilidades
def carregar_config() -> dict:
    return json.loads(ARQ_CONFIG.read_text(encoding="utf-8"))


def ler_modo(config: dict) -> str:
    try:
        modo = ARQ_MODO.read_text(encoding="utf-8").strip()
    except OSError:
        return config.get("modo_padrao", "skills")
    return modo if modo in MODOS else config.get("modo_padrao", "skills")


_PADROES_SEGREDO = [
    (re.compile(r"-----BEGIN[\s\S]*?-----END[^-]*-----"), "<chave-pem>"),
    (
        re.compile(r"\b(?:postgres(?:ql)?|redis|rediss|mysql|mongodb(?:\+srv)?|amqp)://\S+", re.I),
        "<url-banco>",
    ),
    (re.compile(r"\bhttps?://[^\s/@]+:[^\s/@]+@\S+", re.I), "<url-com-credencial>"),
    (
        re.compile(r"\b(?:sk-|ghp_|gho_|ghs_|github_pat_|xox[abp]-|AKIA)[A-Za-z0-9_\-]{10,}"),
        "<token>",
    ),
    # Só `chave=valor`/`chave: valor`: "trocar a senha do usuário" fica intacto.
    (
        re.compile(r"(?i)\b(api[_-]?key|token|secret|senha|password|passwd)\s*[:=]\s*\S+"),
        r"\1=<segredo>",
    ),
    (re.compile(r"(?i)\bbearer\s+\S+"), "Bearer <segredo>"),
    (re.compile(r"\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b"), "<usuario@host>"),
    (re.compile(r"\b\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?\b"), "<ip>"),
    (re.compile(r"\b[A-Za-z0-9_\-]{40,}\b"), "<valor-longo>"),
]


def mascarar(texto: str) -> str:
    """Remove o que parece segredo antes de sair da máquina ou ir para o log."""
    for padrao, troca in _PADROES_SEGREDO:
        texto = padrao.sub(troca, texto)
    return texto


def _frontmatter(caminho: Path) -> dict:
    """Lê `chave: valor` do frontmatter YAML simples (sem dependências)."""
    try:
        texto = caminho.read_text(encoding="utf-8")
    except OSError:
        return {}
    if not texto.startswith("---"):
        return {}
    fim = texto.find("\n---", 3)
    if fim < 0:
        return {}
    dados: dict = {}
    for linha in texto[3:fim].splitlines():
        if ":" not in linha or linha.startswith((" ", "\t", "#")):
            continue
        chave, valor = linha.split(":", 1)
        dados[chave.strip()] = valor.strip().strip('"').strip("'")
    return dados


def catalogo() -> dict:
    """Skills e especialistas, com cache invalidado pelo mtime das pastas."""
    arquivos = sorted(DIR_SKILLS.glob("*/SKILL.md")) + sorted(DIR_AGENTES.glob("*.md"))
    assinatura = max((p.stat().st_mtime for p in arquivos), default=0.0)
    assinatura = max(assinatura, DIR_SKILLS.stat().st_mtime if DIR_SKILLS.exists() else 0.0)
    try:
        cache = json.loads(ARQ_CATALOGO.read_text(encoding="utf-8"))
        if cache.get("assinatura") == assinatura:
            return cache
    except (OSError, ValueError):
        pass
    skills = {}
    for caminho in sorted(DIR_SKILLS.glob("*/SKILL.md")):
        meta = _frontmatter(caminho)
        if meta.get("description"):
            skills[caminho.parent.name] = meta["description"]
    especialistas = {}
    for caminho in sorted(DIR_AGENTES.glob("*.md")):
        meta = _frontmatter(caminho)
        if meta.get("type") == "agent" and meta.get("name"):
            especialistas[meta["name"]] = meta.get("description", "")
    especialistas["general-purpose"] = (
        "Generic agent for research and multi-step tasks that fit no specialist"
    )
    dados = {"assinatura": assinatura, "skills": skills, "especialistas": especialistas}
    try:
        DIR_ESTADO.mkdir(parents=True, exist_ok=True)
        ARQ_CATALOGO.write_text(json.dumps(dados, ensure_ascii=False), encoding="utf-8")
    except OSError:
        pass
    return dados


def fase_ativa() -> str | None:
    """Fase PREVC em andamento, lida do status.yaml do dotcontext."""
    try:
        texto = ARQ_WORKFLOW.read_text(encoding="utf-8")
    except OSError:
        return None
    m = re.search(r"^\s*current_phase:\s*([PREVC])\b", texto, re.M)
    if not m:
        return None
    fase = m.group(1)
    bloco = re.search(rf"^\s{{2}}{fase}:\s*\n((?:\s{{4}}.*\n?)+)", texto, re.M)
    status = re.search(r"status:\s*([\w-]+)", bloco.group(1)) if bloco else None
    if status and status.group(1).startswith(("completed", "filled", "skipped")):
        return None
    return fase


# ------------------------------------------------------------- registro
def ler_ultima_decisao(session_id: str | None = None) -> dict | None:
    """Última decisão do log; com `session_id`, a última daquela sessão
    (sessões em paralelo não herdam a tarefa uma da outra)."""
    try:
        with ARQ_LOG.open("rb") as arq:
            arq.seek(0, os.SEEK_END)
            tamanho = arq.tell()
            arq.seek(max(0, tamanho - 65536))
            linhas = arq.read().decode("utf-8", "replace").strip().splitlines()
    except OSError:
        return None
    for linha in reversed(linhas):
        try:
            d = json.loads(linha)
        except ValueError:
            continue
        if session_id is None or d.get("session_id") == session_id:
            return d
    return None


def skill_ja_indicada(session_id: str, skill: str) -> bool:
    """Se esta skill já foi indicada nesta sessão (evita repetir a instrução)."""
    try:
        with ARQ_LOG.open("rb") as arq:
            arq.seek(0, os.SEEK_END)
            arq.seek(max(0, arq.tell() - 65536))
            linhas = arq.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return False
    for linha in linhas:
        try:
            d = json.loads(linha)
        except ValueError:
            continue
        if d.get("session_id") == session_id and d.get("skill") == skill:
            return True
    return False


def registrar(config: dict, decisao: dict) -> None:
    try:
        DIR_ESTADO.mkdir(parents=True, exist_ok=True)
        if ARQ_LOG.exists() and ARQ_LOG.stat().st_size > config.get("log_max_bytes", 5242880):
            ARQ_LOG.replace(ARQ_LOG.with_suffix(".jsonl.1"))
        with ARQ_LOG.open("a", encoding="utf-8") as arq:
            arq.write(json.dumps(decisao, ensure_ascii=False) + "\n")
    except OSError:
        pass


def texto_status(config: dict, decisao: dict | None, modo: str) -> str:
    aviso = ""
    if (CLAUDE_DIR / "skills").exists() or (RAIZ / ".agents" / "skills").exists():
        aviso = "⚠ skills duplicadas · "
    if modo == "off":
        return aviso + "roteador: off"
    if decisao is None:
        return aviso + f"roteador: {modo}"
    if decisao.get("falha") == "chave_ausente":
        return aviso + "roteador: sem chave"
    skill = decisao.get("skill") or "—"
    chance = decisao.get("skill_chance")
    parte_skill = f"skill: {skill}" + (
        f" {chance:.2f}" if isinstance(chance, float) and decisao.get("skill") else ""
    )
    ms = decisao.get("jev_ms")
    sufixo = f" · {ms}ms" if ms else ""
    if decisao.get("atalho") == "comando":
        return aviso + f"roteador: comando /{decisao.get('comando')} · {parte_skill}"
    if decisao.get("atalho") == "direto":
        return aviso + "roteador: direto (>>)"
    if modo == "skills":
        prefixo = "seletor"
        if decisao.get("falha"):
            prefixo = "seletor: jev indisponível"
        return aviso + f"{prefixo} · {parte_skill}{sufixo}"
    nivel = decisao.get("nivel_final", "?")
    rotulo = config["niveis"].get(nivel, {}).get("rotulo", "?")
    if decisao.get("falha"):
        return aviso + f"roteador: jev indisponível → {rotulo.lower()} · {parte_skill}"
    conf = decisao.get("nivel_confianca")
    conf_txt = f" {conf:.2f}" if isinstance(conf, float) else ""
    escalada = decisao.get("escalada")
    seta = f" ↑{escalada}" if escalada else ""
    nome_nivel = {"dificil": "difícil"}.get(nivel, nivel)
    return (
        aviso
        + f"roteador: {nome_nivel}{conf_txt}{seta} → {decisao.get('especialista')} ({rotulo})"
        + f" · {parte_skill}{sufixo}"
    )


def gravar_status(texto: str) -> None:
    try:
        DIR_ESTADO.mkdir(parents=True, exist_ok=True)
        ARQ_STATUS.write_text(f"{_ROTULO_MAQUINA}{texto}\n", encoding="utf-8")
    except OSError:
        pass


# --------------------------------------------------------------- atalhos
_RE_ATALHO = re.compile(r"^\s*(#(?:rapido|padrao|profundo)|\$[a-z0-9][a-z0-9-]*)\s+", re.I)


def ler_atalhos(prompt: str, config: dict, skills: dict) -> tuple[str, str | None, str | None]:
    """Remove `#nivel` e `$skill` do início; devolve (texto, nivel, skill)."""
    por_atalho = {v["atalho"]: k for k, v in config["niveis"].items()}
    nivel = skill = None
    texto = prompt + " "
    for _ in range(2):
        m = _RE_ATALHO.match(texto)
        if not m:
            break
        token = m.group(1).lower()
        if token.startswith("#"):
            nivel = por_atalho.get(token[1:])
        elif token[1:] in skills:
            skill = token[1:]
        else:
            break
        texto = texto[m.end():]
    return texto.strip(), nivel, skill


# ------------------------------------------------------------------- Jev
def _criterios_choice(itens: dict, limite: int = 400) -> dict:
    return {nome: (desc or nome)[:limite] for nome, desc in itens.items()}


def montar_perguntas(cat: dict, elegiveis: dict, anterior: dict | None) -> dict:
    perguntas = {
        "nivel": {
            "type": "choice",
            "instructions": (
                "How demanding is the software engineering request in `mensagem` for the "
                "project described in `projeto`? Judge the work needed, not the tone."
            ),
            "criteria": {
                "simples": {
                    "what": "Small, localized change or quick factual question",
                    "examples": [
                        "change a text, label or color",
                        "rename something",
                        "tweak one file",
                        "where is X defined?",
                    ],
                },
                "rotina": {
                    "what": "Common feature or task following existing patterns, in one layer",
                    "examples": [
                        "new Flutter screen",
                        "new handler or test following the existing pattern",
                        "write docs",
                    ],
                },
                "dificil": {
                    "what": "Hard, risky or cross-cutting work",
                    "examples": [
                        "bug with unknown cause",
                        "change spanning Rust, Python and Flutter",
                        ".proto contract change",
                        "database migration, RLS or multi-tenant isolation",
                        "concurrency, idempotency, debounce",
                        "security",
                        "deploy or VPS infrastructure",
                        "AI engine behavior",
                        "planning or architecture",
                    ],
                },
            },
        },
        "especialista": {
            "type": "choice",
            "instructions": (
                "Which specialist agent should do the work requested in `mensagem`?"
            ),
            "criteria": _criterios_choice(cat["especialistas"]),
        },
        "risco": {
            "type": "noul",
            "instructions": (
                "Could carrying out the request in `mensagem` break something that already "
                "works in the project?"
            ),
            "criteria": {
                "true": "The change touches working behavior, shared code, contracts, data or deploy",
                "false": "Read-only, isolated or purely additive work",
            },
        },
        "entregavel_texto": {
            "type": "noul",
            "instructions": (
                "Is the deliverable of `mensagem` a text for the user to read (analysis, plan, "
                "explanation, review report, prompt) rather than a change to code or files?"
            ),
            "criteria": {
                "true": "The user wants to read an answer or document",
                "false": "The user wants code, config or files changed",
            },
        },
    }
    if elegiveis:
        criterios = _criterios_choice(elegiveis)
        criterios["nenhuma"] = (
            "No listed skill applies: the request needs no specialized procedure"
        )
        perguntas["skill"] = {
            "type": "choice",
            "instructions": (
                "Which skill (a written procedure) should guide the work requested in "
                "`mensagem`? Pick a skill only when the user asks to carry out the activity "
                "that the skill describes. Answering a question, explaining a concept or "
                "making a small edit needs no skill: choose `nenhuma`."
            ),
            "criteria": criterios,
        }
    if anterior:
        perguntas["continuacao"] = {
            "type": "noul",
            "instructions": (
                "Does `mensagem` continue or confirm the task in `tarefa_anterior` (e.g. 'yes', "
                "'go on', 'commit it', an adjustment to what was just done) instead of starting "
                "a new subject?"
            ),
            "criteria": {
                "true": "Follow-up, confirmation or adjustment of the previous task",
                "false": "A new, unrelated request",
            },
        }
    return perguntas


class FalhaJev(Exception):
    def __init__(self, motivo: str) -> None:
        super().__init__(motivo)
        self.motivo = motivo


def consultar_jev(config: dict, state: dict, perguntas: dict) -> tuple[dict, int]:
    """Uma requisição HTTP ao Jev. Imports de rede só aqui (partida rápida)."""
    import urllib.error
    import urllib.request

    chave = (os.environ.get("TYPESAFE_API_KEY") or "").strip()
    if not chave:
        raise FalhaJev("chave_ausente")
    corpo = json.dumps(
        {"model": config["jev"]["modelo"], "state": state, "questions": perguntas},
        ensure_ascii=False,
    ).encode("utf-8")
    req = urllib.request.Request(
        config["jev"]["url"],
        data=corpo,
        headers={"Authorization": f"Bearer {chave}", "Content-Type": "application/json"},
        method="POST",
    )
    inicio = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=config["jev"]["timeout_s"]) as resp:
            dados = json.load(resp)
    except urllib.error.HTTPError as exc:
        # Só o status: o corpo pode ecoar a mensagem.
        raise FalhaJev(f"http_{exc.code}") from None
    except TimeoutError:
        raise FalhaJev("timeout") from None
    except (urllib.error.URLError, OSError, ValueError) as exc:
        raise FalhaJev(f"rede_{type(exc).__name__}") from None
    return dados.get("answers", {}), int((time.perf_counter() - inicio) * 1000)


# --------------------------------------------------------------- decisão
_ORDEM = ["simples", "rotina", "dificil"]


def _subir(nivel: str) -> str:
    return _ORDEM[min(_ORDEM.index(nivel) + 1, len(_ORDEM) - 1)]


def _resolver_par(config: dict, probs: dict, texto: str) -> tuple[str | None, bool]:
    """Desempate entre skills parecidas. Devolve (skill, aplicou_regra)."""
    ordenadas = sorted(
        ((k, v) for k, v in probs.items() if k != "nenhuma"), key=lambda kv: -kv[1]
    )
    if len(ordenadas) < 2:
        return None, False
    (a, pa), (b, pb) = ordenadas[0], ordenadas[1]
    lim = config["limiares"]["soma_par_concorrente_min"]
    baixo = texto.lower()
    for regra in config["pares_concorrentes"]:
        if {a, b} == set(regra["par"]) and pa + pb > lim:
            if any(g in baixo for g in regra["gatilhos"]):
                return regra["especializada"], True
            return a, True
    return None, False


def decidir(
    config: dict,
    respostas: dict,
    *,
    texto: str,
    anterior: dict | None,
    nivel_forcado: str | None = None,
    skill_forcada: str | None = None,
    fase_skill: str | None = None,
) -> dict:
    """Política explícita: respostas do Jev → nível, modelo, especialista, skill."""
    lim = config["limiares"]
    d: dict = {}

    # Continuação herda a tarefa anterior.
    cont = respostas.get("continuacao", {}).get("noul")
    d["continuacao"] = cont
    herda = anterior is not None and isinstance(cont, (int, float)) and cont > lim["continuacao_herda"]
    d["retomar"] = bool(herda)

    # Nível.
    r_nivel = respostas.get("nivel", {})
    d["nivel_jev"] = r_nivel.get("choice")
    d["nivel_confianca"] = r_nivel.get("confidence")
    d["risco"] = respostas.get("risco", {}).get("noul")
    escalada = None
    if nivel_forcado:
        nivel = nivel_forcado
        escalada = "manual"
    else:
        nivel = r_nivel.get("choice") if r_nivel.get("choice") in _ORDEM else "rotina"
        risco = d["risco"] or 0.0
        conf = r_nivel.get("confidence")
        # Sobe no máximo um nível; só registra a escalada se mudou algo.
        motivo_sobe = None
        if risco > lim["risco_sobe_nivel"]:
            motivo_sobe = "risco"
        elif isinstance(conf, (int, float)) and conf < lim["confianca_nivel_min"]:
            motivo_sobe = "confianca"
        if motivo_sobe and _subir(nivel) != nivel:
            nivel, escalada = _subir(nivel), motivo_sobe
        if herda and anterior.get("nivel_final") in _ORDEM:
            if _ORDEM.index(anterior["nivel_final"]) > _ORDEM.index(nivel):
                nivel, escalada = anterior["nivel_final"], "continuacao"
    d["nivel_final"] = nivel
    d["escalada"] = escalada
    d["modelo"] = config["niveis"][nivel]["modelo"]

    # Skill.
    r_skill = respostas.get("skill", {})
    probs = r_skill.get("probabilities") or {}
    ordenadas = sorted(probs.items(), key=lambda kv: -kv[1])
    d["skill_candidata"] = r_skill.get("choice")
    d["skill_chance"] = probs.get(r_skill.get("choice")) if r_skill else None
    d["skill_confianca"] = r_skill.get("confidence")
    if len(ordenadas) > 1:
        d["skill_segunda"], d["skill_segunda_chance"] = ordenadas[1]
    skill, motivo = None, None
    if skill_forcada:
        skill, motivo = skill_forcada, "manual"
    elif fase_skill:
        skill, motivo = fase_skill, "fase"
    else:
        # Skill nova aceita pelo Jev vence a herdada (ex.: "pode commitar" no
        # meio de uma investigação → commit-message); sem ela, herda.
        escolha = r_skill.get("choice")
        chance = d["skill_chance"] or 0.0
        conf = r_skill.get("confidence") or 0.0
        if (
            escolha
            and escolha != "nenhuma"
            and chance > lim["chance_skill_min"]
            and conf >= lim["confianca_skill_min"]
        ):
            skill, motivo = escolha, "jev"
        else:
            par, aplicou = _resolver_par(config, probs, texto)
            if aplicou:
                skill, motivo = par, "par"
            elif herda and anterior.get("skill"):
                skill, motivo = anterior["skill"], "continuacao"
    d["skill"] = skill
    d["skill_motivo"] = motivo

    # Especialista.
    r_esp = respostas.get("especialista", {})
    d["especialista_jev"] = r_esp.get("choice")
    d["especialista_confianca"] = r_esp.get("confidence")
    if herda and anterior.get("especialista"):
        esp = anterior["especialista"]
    elif r_esp.get("choice") and (r_esp.get("confidence") or 0.0) >= lim["confianca_especialista_min"]:
        esp = r_esp["choice"]
    else:
        esp = config["skill_para_especialista"].get(skill or "", "general-purpose")
    d["especialista"] = esp
    return d


def decisao_de_falha(config: dict, motivo: str, skill_forcada: str | None, fase_skill: str | None) -> dict:
    nivel = config.get("nivel_em_falha", "rotina")
    skill = skill_forcada or fase_skill
    return {
        "falha": motivo,
        "nivel_final": nivel,
        "modelo": config["niveis"][nivel]["modelo"],
        "especialista": "general-purpose",
        "skill": skill,
        "skill_motivo": ("manual" if skill_forcada else "fase") if skill else "falha",
        "retomar": False,
    }


# ------------------------------------------------------------- contexto
def contexto_para_claude(modo: str, d: dict, ja_indicada: bool) -> str:
    skill = d.get("skill")
    caminho = f".context/skills/{skill}/SKILL.md" if skill else None
    if modo == "skills":
        if not skill:
            return ""
        if ja_indicada:
            return f"[seletor de skill] A skill `{skill}` já foi indicada nesta sessão; continue seguindo-a."
        return (
            f"[seletor de skill] Skill indicada: `{skill}`. Leia e siga `{caminho}` antes de "
            "responder. Skills citadas por ela ficam em `.context/skills/<slug>/SKILL.md` "
            "(ou via MCP dotcontext `skill getContent`)."
        )
    linhas = [
        "[roteador] Decisão para esta mensagem:",
        f"- nível: {d.get('nivel_final')} · modelo: {d.get('modelo')} · especialista: {d.get('especialista')}",
        f"- retomar: {'sim' if d.get('retomar') else 'não'} · entregável em texto: "
        f"{'sim' if d.get('entregavel_texto') else 'não'}",
        f"- skill: {skill or 'nenhuma'}",
    ]
    if d.get("falha"):
        linhas.append(f"- o Jev falhou ({d['falha']}); decisão de segurança aplicada.")
    linhas.append(
        f"Delegue ao subagente `{d.get('especialista')}` com `model: {d.get('modelo')}`. Passe a "
        "mensagem do usuário LITERAL (sem os atalhos `#nivel`/`$skill`) e o contexto necessário "
        "(arquivos citados, decisões recentes e regras de memória relevantes: gitflow, sem testes "
        "na máquina local, comentários pt-br, commits sem auto-referência)."
    )
    if skill:
        linhas.append(
            f"Instrua o subagente a ler e seguir `{caminho}` antes de começar; skills citadas por "
            "ela ficam em `.context/skills/<slug>/SKILL.md`."
        )
    if d.get("retomar"):
        linhas.append(
            "É continuação: se já houver subagente desta tarefa, continue com SendMessage em vez de abrir outro."
        )
    linhas.append(
        "Ao final: se o entregável for texto, entregue ao usuário o texto completo do subagente; se "
        "for código, responda com um resumo do que mudou, arquivos e pendências. Se um subagente opus "
        "não entregar após 2 cobranças, redespache no sonnet e avise. Se ele parar por limite de "
        "sessão da API, avise e retome com SendMessage depois."
    )
    return "\n".join(linhas)


# ------------------------------------------------------------------ fluxo
def processar(entrada: dict, config: dict, *, seco: bool = False) -> tuple[dict, str]:
    """Decide para uma mensagem. Devolve (registro, additionalContext)."""
    modo = ler_modo(config)
    prompt = entrada.get("prompt") or ""
    session_id = entrada.get("session_id") or ""
    agora = datetime.now(timezone.utc)
    base = {
        "horario": agora.isoformat(timespec="seconds"),
        "session_id": session_id,
        "modo": modo,
        "mensagem": mascarar(prompt)[:200],
    }
    if modo == "off":
        return base | {"atalho": "off"}, ""

    texto = prompt.strip()
    if texto.startswith(">>"):
        return base | {"atalho": "direto"}, ""
    cat = catalogo()
    marcador = re.search(r"stub-skill:([a-z0-9-]+)", texto)
    if texto.startswith("/") or marcador:
        nome = marcador.group(1) if marcador else texto[1:].split(maxsplit=1)[0] if len(texto) > 1 else ""
        skill = nome if nome in cat["skills"] else None
        return base | {"atalho": "comando", "comando": nome, "skill": skill,
                       "skill_motivo": "comando" if skill else None}, ""

    texto, nivel_forcado, skill_forcada = ler_atalhos(texto, config, cat["skills"])
    atalho = "manual" if (nivel_forcado or skill_forcada) else None

    fase = fase_ativa()
    fase_skill = config["fase_para_skill"].get(fase) if fase else None

    anterior = ler_ultima_decisao(session_id) if session_id else None
    if anterior:
        try:
            quando = datetime.fromisoformat(anterior["horario"])
            janela = timedelta(minutes=config.get("janela_tarefa_anterior_min", 120))
            if agora - quando > janela or anterior.get("atalho") in ("direto", "comando", "off"):
                anterior = None
        except (KeyError, ValueError):
            anterior = None

    elegiveis = {
        s: desc
        for s, desc in cat["skills"].items()
        if not s.startswith(tuple(config["skills_fora_do_jev_prefixos"]))
    }
    if skill_forcada or fase_skill:
        elegiveis = {}
    state = {
        "mensagem": mascarar(texto)[:2000],
        "projeto": config["projeto"],
    }
    if anterior:
        state["tarefa_anterior"] = {
            "mensagem": anterior.get("mensagem", ""),
            "nivel": anterior.get("nivel_final"),
            "especialista": anterior.get("especialista"),
            "skill": anterior.get("skill"),
        }
    perguntas = montar_perguntas(cat, elegiveis, anterior)
    if modo == "skills":
        # Sem delegação: só a skill (e a continuação, para herdá-la).
        perguntas = {k: v for k, v in perguntas.items() if k in ("skill", "continuacao")}

    if not perguntas:
        respostas, jev_ms, falha = {}, None, None
    else:
        try:
            respostas, jev_ms = consultar_jev(config, state, perguntas)
            falha = None
        except FalhaJev as exc:
            respostas, jev_ms, falha = {}, None, exc.motivo

    if falha:
        d = decisao_de_falha(config, falha, skill_forcada, fase_skill)
    else:
        d = decidir(
            config,
            respostas,
            texto=texto,
            anterior=anterior,
            nivel_forcado=nivel_forcado,
            skill_forcada=skill_forcada,
            fase_skill=fase_skill,
        )
        d["entregavel_texto"] = respostas.get("entregavel_texto", {}).get("noul")
        if isinstance(d["entregavel_texto"], (int, float)):
            d["entregavel_texto"] = d["entregavel_texto"] > 0.5

    # Só no modo `skills` a instrução não se repete: no modo `on` cada
    # subagente começa do zero e precisa do caminho de novo.
    ja = (
        modo == "skills"
        and bool(d.get("skill"))
        and not seco
        and skill_ja_indicada(session_id, d["skill"])
    )
    registro = base | {"atalho": atalho, "fase": fase, "jev_ms": jev_ms} | d
    registro["injetado"] = (
        "caminho" if d.get("skill") and not ja else "ja_indicada" if ja else "nada"
    )
    contexto = contexto_para_claude(modo, d, ja)
    if modo == "on":
        registro["injetado"] = "delegacao+" + registro["injetado"]
    return registro, contexto


def cli(argv: list[str]) -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    config = carregar_config()
    acao = argv[0] if argv else "status"
    if acao in MODOS:
        DIR_ESTADO.mkdir(parents=True, exist_ok=True)
        ARQ_MODO.write_text(acao + "\n", encoding="utf-8")
        gravar_status(texto_status(config, None, acao))
        print(f"roteador: modo {acao}")
        if acao == "on":
            print("Lembrete: ponha a sessão principal no Haiku com /model haiku.")
        return 0
    modo = ler_modo(config)
    ultima = ler_ultima_decisao()
    print(f"máquina: {MACHINE_PREFIX}")
    print(f"modo: {modo}")
    print("chave TYPESAFE_API_KEY: " + ("presente" if os.environ.get("TYPESAFE_API_KEY") else "AUSENTE"))
    print("última decisão: " + (texto_status(config, ultima, modo) if ultima else "nenhuma"))
    return 0


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--cli":
        return cli(sys.argv[2:])
    # O gancho nunca pode travar a mensagem: qualquer erro sai em silêncio.
    try:
        bruto = sys.stdin.buffer.read().decode("utf-8", "replace")
        entrada = json.loads(bruto or "{}")
        config = carregar_config()
        registro, contexto = processar(entrada, config)
        registro["gancho_ms"] = int((time.perf_counter() - _INICIO) * 1000)
        registro["maquina"] = MACHINE_PREFIX
        registrar(config, registro)
        gravar_status(texto_status(config, registro, registro.get("modo", "skills")))
        if contexto:
            saida = {
                "hookSpecificOutput": {
                    "hookEventName": "UserPromptSubmit",
                    "additionalContext": contexto,
                }
            }
            sys.stdout.buffer.write(json.dumps(saida, ensure_ascii=False).encode("utf-8"))
    except Exception as exc:  # noqa: BLE001 - o gancho não pode derrubar a sessão
        try:
            gravar_status(f"roteador: erro interno ({type(exc).__name__})")
        except Exception:  # noqa: BLE001
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
