"""Candidatos a valor de entidade encontrados por código.

O Jev não gera texto: ele **escolhe** entre candidatos que o código achou na
mensagem. Assim o valor gravado é sempre um pedaço do que o cliente escreveu,
nunca uma invenção. O que não tem candidato (`livre`) fica para a LLM pequena,
conferida depois pelo Jev.

Funções puras, sem I/O.
"""

from __future__ import annotations

import re
import unicodedata
from datetime import date, timedelta

_NUMERO = r"\d{1,3}(?:[.\s]\d{3})+|\d+(?:[.,]\d+)?"

# Quantidade: "500", "1.000 unidades", "2 mil", "10k".
_RE_QUANTIDADE = re.compile(
    rf"(?<![\w/])(?:{_NUMERO})\s*(?:mil|k|milheiros?|unidades?|un\.?|pe[çc]as?|"
    r"c[óo]pias?|folhas?|exemplares?)?(?![\w/])",
    re.IGNORECASE,
)
# Dimensões: "9x5", "9 x 5 cm", "21,0x29,7cm", "A4".
_RE_DIMENSOES = re.compile(
    r"(?<!\w)(?:\d+(?:[.,]\d+)?\s*[x×]\s*\d+(?:[.,]\d+)?(?:\s*[x×]\s*\d+(?:[.,]\d+)?)?"
    r"\s*(?:cm|mm|m)?|A[0-6])(?!\w)",
    re.IGNORECASE,
)
# Cores de impressão: "4x0", "4x4", "1x0", "colorido", "preto e branco".
_RE_CORES = re.compile(
    r"(?<!\d)[0-4]\s*[x/]\s*[0-4](?!\d)|colorid[oa]s?|preto\s+e\s+branco|p\s*&\s*b",
    re.IGNORECASE,
)
_GENERICOS = (_RE_QUANTIDADE, _RE_DIMENSOES, _RE_CORES)

_MESES = {
    "janeiro": 1, "fevereiro": 2, "marco": 3, "abril": 4, "maio": 5,
    "junho": 6, "julho": 7, "agosto": 8, "setembro": 9, "outubro": 10,
    "novembro": 11, "dezembro": 12,
}  # fmt: skip
_RE_DATA_NUM = re.compile(r"(?<!\d)(\d{1,2})[/.-](\d{1,2})(?:[/.-](\d{2,4}))?(?!\d)")
_RE_DATA_EXT = re.compile(
    r"(?<!\d)(\d{1,2})\s+de\s+([a-zç]+)(?:\s+de\s+(\d{4}))?", re.IGNORECASE
)
_RELATIVAS = {"hoje": 0, "amanha": 1, "depois de amanha": 2}
_DIAS_SEMANA = {
    "segunda": 0, "terca": 1, "quarta": 2, "quinta": 3, "sexta": 4,
    "sabado": 5, "domingo": 6,
}  # fmt: skip


def _sem_acento(texto: str) -> str:
    return "".join(
        c
        for c in unicodedata.normalize("NFD", texto.lower())
        if unicodedata.category(c) != "Mn"
    )


def _unicos(valores: list[str], limite: int) -> list[str]:
    vistos: list[str] = []
    for v in valores:
        v = v.strip(" ,.;:")
        if v and v not in vistos:
            vistos.append(v)
    return vistos[:limite]


def por_regex(
    mensagem: str, padroes: tuple[str, ...] = (), limite: int = 12
) -> list[str]:
    """Trechos da mensagem que casam com os padrões do tipo.

    Sem padrões próprios, usa os genéricos (quantidade, dimensões, cores). Um
    padrão inválido cadastrado pelo tenant é ignorado, não derruba a análise.
    """
    compilados: list[re.Pattern[str]] = []
    for p in padroes:
        try:
            compilados.append(re.compile(p, re.IGNORECASE))
        except re.error:
            continue
    achados: list[str] = []
    for padrao in compilados or list(_GENERICOS):
        achados.extend(m.group(0) for m in padrao.finditer(mensagem))
    return _unicos(achados, limite)


def por_lista(mensagem: str, opcoes: tuple[str, ...]) -> list[str]:
    """Opções conhecidas do tipo — todas vão ao `Choice`, citadas ou não.

    O Jev decide qual o cliente quis; a lista inteira é o universo possível
    (a doc: o modelo não escolhe o que não está entre as opções).
    """
    return _unicos(list(opcoes), 240)


def _iso(dia: int, mes: int, ano: int) -> str | None:
    try:
        return date(ano, mes, dia).isoformat()
    except ValueError:
        return None


def por_data(mensagem: str, hoje: date) -> dict[str, str]:
    """Datas citadas → ISO. Chave: o trecho como o cliente escreveu.

    O Jev não faz conta com datas (jaggedness do jev-1.13): ele só escolhe qual
    trecho é o prazo; a montagem da data é aqui.
    """
    achados: dict[str, str] = {}
    for m in _RE_DATA_NUM.finditer(mensagem):
        dia, mes = int(m.group(1)), int(m.group(2))
        ano_txt = m.group(3)
        ano = int(ano_txt) if ano_txt else hoje.year
        if ano < 100:
            ano += 2000
        iso = _iso(dia, mes, ano)
        if iso and not ano_txt and iso < hoje.isoformat():
            iso = _iso(dia, mes, ano + 1)
        if iso:
            achados[m.group(0)] = iso
    for m in _RE_DATA_EXT.finditer(mensagem):
        mes_ext = _MESES.get(_sem_acento(m.group(2)))
        if not mes_ext:
            continue
        ano = int(m.group(3)) if m.group(3) else hoje.year
        iso = _iso(int(m.group(1)), mes_ext, ano)
        if iso and not m.group(3) and iso < hoje.isoformat():
            iso = _iso(int(m.group(1)), mes_ext, ano + 1)
        if iso:
            achados[m.group(0)] = iso
    normal = _sem_acento(mensagem)
    for palavra, dias in sorted(_RELATIVAS.items(), key=lambda kv: -len(kv[0])):
        if re.search(rf"(?<!\w){palavra}(?!\w)", normal):
            achados.setdefault(palavra, (hoje + timedelta(days=dias)).isoformat())
    for nome, alvo in _DIAS_SEMANA.items():
        if re.search(rf"(?<!\w){nome}(?:-feira)?(?!\w)", normal):
            delta = (alvo - hoje.weekday()) % 7 or 7
            achados.setdefault(nome, (hoje + timedelta(days=delta)).isoformat())
    return achados


def esta_no_texto(valor: str, mensagem: str) -> bool:
    """O valor aparece na mensagem (sem diferenciar acento nem caixa)?"""
    v = _sem_acento(valor).strip()
    return bool(v) and v in _sem_acento(mensagem)
