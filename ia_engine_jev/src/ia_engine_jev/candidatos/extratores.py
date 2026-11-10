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


def _normal_com_origem(texto: str) -> tuple[str, list[int]]:
    """Texto sem acento, minúsculo e com espaços colapsados, mais o índice do
    caractere original de cada caractere normalizado."""
    saida: list[str] = []
    origem: list[int] = []
    for i, c in enumerate(texto):
        if c.isspace():
            if saida and saida[-1] != " ":
                saida.append(" ")
                origem.append(i)
            continue
        for n in _sem_acento(c):
            saida.append(n)
            origem.append(i)
    return "".join(saida), origem


# Documento (CPF/CNPJ): só dígitos e a pontuação de máscara.
_RE_DOCUMENTO = re.compile(r"[\d.\-/\s]+")
# Tamanho dos blocos da máscara oficial: CPF 000.000.000-00 e
# CNPJ 00.000.000/0000-00.
_BLOCOS_DO_DOCUMENTO = {11: (3, 3, 3, 2), 14: (2, 3, 3, 4, 2)}
# Data já normalizada pela LLM.
_RE_DATA_ISO = re.compile(r"\d{4}-\d{2}-\d{2}")
# Número simples ("1500", "1500,5", "-3") e número com milhar ("1.500,50").
_RE_NUMERO_SIMPLES = re.compile(r"(-?)(\d+)(?:[.,](\d+))?")
_RE_NUMERO_MILHAR = re.compile(r"(-?)(\d{1,3}(?:[.\s]\d{3})+)(?:,(\d+))?")


def _agrupado(inteiro: str, separador: str) -> str:
    """'1500000' → '1' + sep + '500' + sep + '000' (sep já em regex)."""
    grupos: list[str] = []
    while len(inteiro) > 3:
        grupos.insert(0, inteiro[-3:])
        inteiro = inteiro[:-3]
    grupos.insert(0, inteiro)
    return separador.join(grupos)


def _formas_do_numero(inteiro: str, decimais: str | None) -> list[str]:
    """Regex de cada forma escrita do número: sem milhar, com ponto e com
    espaço de milhar; a parte decimal aceita vírgula ou ponto."""
    inteiros = [inteiro]
    if len(inteiro) > 3:
        inteiros += [_agrupado(inteiro, r"\."), _agrupado(inteiro, r"\s")]
    sufixo = rf"[.,]{decimais}" if decimais else ""
    return [i + sufixo for i in inteiros]


def _padrao_numerico(valor: str) -> re.Pattern[str] | None:
    """Padrão que acha o valor numérico na mensagem, ou `None` se o valor não
    é número nem documento.

    - CPF/CNPJ (11 ou 14 dígitos): casa por dígitos, aceitando a máscara que o
      cliente usou ("529.982.247-25" casa "52998224725" e vice-versa). Espaço
      só entre os blocos da máscara oficial ("529 982 247 25"): é a mesma
      regra do servidor (`digitos_delimitados`), que recusa a frase fora desse
      desenho — "11 98765-4321" é telefone, não CPF.
    - Número: casa ignorando separador de milhar ("1500" casa "1.500").

    Vizinho dígito, letra, ou ponto/vírgula seguido de dígito invalida o
    casamento: "500" não é achado dentro de "1.500", nem "12" em "1.2".
    """
    digitos = "".join(c for c in valor if c.isdigit())
    if len(digitos) in (11, 14) and _RE_DOCUMENTO.fullmatch(valor):
        # Forma 1: dígitos com a máscara opcional, sem espaço.
        sem_espaco = r"[.\-/]?".join(digitos)
        # Forma 2: os blocos da máscara oficial, com exatamente um espaço (ou
        # caractere de máscara) entre eles, e sem outro número colado por
        # espaço antes ou depois.
        blocos: list[str] = []
        inicio = 0
        for tamanho in _BLOCOS_DO_DOCUMENTO[len(digitos)]:
            blocos.append(digitos[inicio : inicio + tamanho])
            inicio += tamanho
        em_blocos = r"[ .\-/]".join(blocos)
        return re.compile(
            rf"(?<![\w.,/-])(?:{sem_espaco}|(?<!\d ){em_blocos}(?! \d))"
            r"(?![\w]|[.,/-]\d)"
        )
    formas: list[str] = []
    for regex in (_RE_NUMERO_MILHAR, _RE_NUMERO_SIMPLES):
        if m := regex.fullmatch(valor):
            inteiro = re.sub(r"\D", "", m.group(2))
            formas += [
                f"{m.group(1)}{f}" for f in _formas_do_numero(inteiro, m.group(3))
            ]
    if not formas:
        return None
    # Forma mais longa primeiro: "1.500,50" antes de "1.500".
    alternativas = "|".join(
        f"(?:{f})" for f in sorted(set(formas), key=len, reverse=True)
    )
    return re.compile(rf"(?<![\w.,])(?:{alternativas})(?![\w]|[.,]\d)")


def trecho_no_texto(valor: str, mensagem: str) -> str:
    """O trecho da mensagem, como o cliente escreveu, onde o valor aparece.

    A busca ignora acento, caixa e espaços repetidos, mas só aceita palavra
    inteira (o servidor confere assim). Devolve o recorte original da
    mensagem — é ele a `frase_origem` que o servidor procura. Sem ocorrência,
    devolve vazio: valor sem frase não é gravado.

    Valor numérico casa pela forma, não pela letra: CPF/CNPJ por dígitos
    (com ou sem máscara) e número sem olhar o separador de milhar. O recorte
    devolvido é o da mensagem, com a máscara e a pontuação do cliente.

    Limitação conhecida (regra estrita, de propósito): booleano e id de
    lista normalizados pela LLM ("true", "couche_fosco") só acham frase se
    estiverem escritos assim na mensagem; sem recorte literal, o campo não
    sai — não se inventa frase. Data em ISO tem caminho próprio, em
    `frase_da_data`.
    """
    padrao = _padrao_numerico(valor.strip())
    if padrao is not None:
        achado = padrao.search(mensagem)
        return achado.group(0) if achado else ""
    alvo, _ = _normal_com_origem(valor.strip())
    alvo = alvo.strip()
    if not alvo:
        return ""
    normal, origem = _normal_com_origem(mensagem)
    inicio = 0
    while (pos := normal.find(alvo, inicio)) >= 0:
        fim = pos + len(alvo)
        antes_ok = pos == 0 or not normal[pos - 1].isalnum()
        depois_ok = fim == len(normal) or not normal[fim].isalnum()
        if antes_ok and depois_ok:
            ate = origem[fim - 1] + 1
            # Acento já decomposto na mensagem (NFD) fica com a letra.
            while ate < len(mensagem) and unicodedata.category(mensagem[ate]) == "Mn":
                ate += 1
            return mensagem[origem[pos] : ate]
        inicio = pos + 1
    return ""


def frase_da_data(iso: str, mensagem: str, hoje: date) -> str:
    """O trecho da mensagem que o código lê como a data `iso` (AAAA-MM-DD).

    A LLM devolve a data normalizada; o cliente escreveu "dia 3 de maio",
    "03/05", "amanhã" ou "sexta". `por_data` faz a conta em código, e só o
    trecho cuja data calculada é exatamente `iso` vira frase: se a LLM e o
    código discordam, não há frase e o campo não sai. O servidor confere de
    novo (`frase_sustenta_data`).
    """
    for trecho, data in por_data(mensagem, hoje).items():
        if data != iso:
            continue
        # Relativas e dias da semana são chaves sem acento ("amanha"); o
        # recorte devolvido é o que está na mensagem ("amanhã").
        original = trecho if trecho in mensagem else trecho_no_texto(trecho, mensagem)
        if original:
            return original
    return ""


def _como_o_servidor_compara(texto: str) -> str:
    """Caixa e espaço repetido não contam; acento conta (o servidor não o
    normaliza). Espelha o `normalizar` de `endereco.rs`."""
    return " ".join(texto.split()).lower()


def valor_e_frase(
    valor: str, mensagem: str, hoje: date | None = None
) -> tuple[str, str] | None:
    """(valor a enviar, frase de origem) de um campo do cartão, ou `None`
    se a mensagem não traz o valor — campo sem frase não é enviado.

    O servidor exige, no campo de texto, o valor dentro da frase, comparando
    acento letra a letra. A cópia da LLM pode vir sem o acento do cliente
    ("sao paulo" para "São Paulo"): nesse caso o valor enviado passa a ser o
    próprio recorte, igual à frase. Quando a cópia só difere em caixa ou
    espaço, ela fica como veio — o servidor já aceita, e um id de lista
    escrito pela LLM ("couche") não é trocado à toa pelo texto do cliente.

    O tipo do campo não chega ao Jev (o `CampoPendente` do contrato só tem
    slug, nome, descrição e dica); por isso a troca vale para todo valor que
    não é número nem documento. Em campo de lista cujo id é a forma sem
    acento do que o cliente escreveu, a troca faz o servidor recusar o id.

    Valor com cara de número ou documento segue com o valor da LLM, e a frase
    é o recorte com a máscara do cliente. Em todo tipo o servidor exige a
    frase inteira na mensagem; além disso, pelo tipo do catálogo:
    - `cpf`/`cnpj`: os dígitos do valor precisam estar nos dígitos da frase
      (a máscara não importa; espaço só entre os blocos oficiais) — o par
      passa;
    - `numero`: um número da frase tem de ser o valor — o par passa;
    - data: a frase tem de trazer o dia (número, dia da semana, "amanhã"). A
      data em ISO que a LLM devolveu sai com o trecho que `por_data` lê como
      essa mesma data (`frase_da_data`);
    - lista: a frase tem de trazer o rótulo, o id ou uma palavra própria da
      opção; booleano: só a frase é conferida;
    - `texto`: o valor precisa estar dentro da frase, letra a letra (só caixa
      e espaço não contam). Telefone ou CEP em campo `texto` com máscara
      diferente da do valor ("11987654321" contra "11 98765-4321") é
      recusado pelo servidor. É falha fechada, de propósito: o campo não é
      gravado, nada errado entra. Trocar o valor pelo recorte só aqui
      exigiria saber o tipo, que o Jev não recebe.
    """
    v = valor.strip()
    frase = trecho_no_texto(v, mensagem)
    if not frase and _RE_DATA_ISO.fullmatch(v):
        frase = frase_da_data(v, mensagem, hoje or date.today())
        return (v, frase) if frase else None
    if not frase:
        return None
    if _padrao_numerico(v) is not None:
        return v, frase
    if _como_o_servidor_compara(v) != _como_o_servidor_compara(frase):
        return frase, frase
    return v, frase
