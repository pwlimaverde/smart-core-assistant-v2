"""Decisões, limiares, candidatos e perguntas do motor Jev — funções puras."""

from __future__ import annotations

from datetime import date

from ia_engine_jev.candidatos import esta_no_texto, por_data, por_lista, por_regex
from ia_engine_jev.config.models import RegraTransferencia
from ia_engine_jev.decisoes.analise import (
    decidir_entidades,
    decidir_intencoes,
    nota_e_sentimento,
    nota_escrita,
)
from ia_engine_jev.decisoes.limiares import Limiares, limiares_de, sinais_de
from ia_engine_jev.decisoes.transferencia import (
    avaliar_trechos,
    comportamento_da_intencao,
    decidir_antes,
    decidir_depois,
    escolher_destino,
)
from ia_engine_jev.domain.jev import (
    EntidadeDef,
    Fluxo,
    IntentDef,
    Trecho,
    TrechoAvaliado,
)
from ia_engine_jev.perguntas import conferencia as pc
from ia_engine_jev.perguntas import entidades as pe
from ia_engine_jev.perguntas import intencoes as pi
from ia_engine_jev.perguntas import transferencia as pt
from ia_engine_jev.perguntas import trechos as ptr
from ia_engine_jev.perguntas.comum import estado_da_mensagem, historico_curto
from ia_engine_jev.typesafe import Nivel, PerguntaChoice, PerguntaNoul, Uso
from tests.jev_fakes import resposta

INTENTS = (
    IntentDef("cartoes", "produtos", "Pedido de cartões de visita", "quero cartões"),
    IntentDef("falar_paulo", "atendimento", "Quer falar com o Paulo", "chama o Paulo"),
)
L = Limiares()


# ------------------------------------------------------------ limiares
def test_limiares_padrao_e_calibrados():
    assert L.limiar_noul("media") == 0.8
    assert L.limiar_noul("desconhecida") == 0.8
    cal = limiares_de(
        {
            "pisos": {"piso_assunto": 0.7, "inexistente": 0.1, "piso_setor": "x"},
            "sensibilidade": {"alta": 0.6},
        }
    )
    assert cal.piso_assunto == 0.7
    assert cal.piso_setor == L.piso_setor
    assert cal.limiar_noul("alta") == 0.6
    assert limiares_de(None) == Limiares()


def test_sinais_com_padroes_e_overrides():
    padrao = sinais_de(None)
    assert padrao.pede_humano.ativo and padrao.irritacao.ativo
    assert not padrao.base_sem_resposta.ativo
    s = sinais_de(
        {
            "irritacao": False,
            "pede_humano": {"sensibilidade": "alta"},
            "base_sem_resposta": {"ativo": True, "sensibilidade": "zzz"},
        }
    )
    assert not s.irritacao.ativo
    assert s.pede_humano.sensibilidade == "alta"
    assert s.base_sem_resposta.ativo and s.base_sem_resposta.sensibilidade == "media"


# ---------------------------------------------------------- candidatos
def test_regex_generico_acha_quantidade_dimensao_e_cores():
    achados = por_regex("quero 1.000 cartões 9x5 cm em 4x0")
    assert "1.000" in " ".join(achados)
    assert any("9x5" in a for a in achados)
    assert any("4x0" in a for a in achados)


def test_regex_proprio_e_padrao_invalido():
    assert por_regex("código AB-12", (r"[A-Z]{2}-\d+", "([")) == ["AB-12"]


def test_lista_e_texto():
    assert por_lista("x", ("couchê", "offset", "couchê")) == ["couchê", "offset"]
    assert esta_no_texto("Couche", "papel couchê fosco")
    assert not esta_no_texto("", "qualquer")


def test_datas_numericas_extenso_e_relativas():
    hoje = date(2026, 9, 28)  # segunda-feira
    d = por_data("para 05/10, ou 3 de outubro, ou amanhã, ou sexta", hoje)
    assert d["05/10"] == "2026-10-05"
    assert d["3 de outubro"] == "2026-10-03"
    assert d["amanha"] == "2026-09-29"
    assert d["sexta"] == "2026-10-02"
    # Data sem ano já passada vai para o ano seguinte.
    assert por_data("dia 01/01", hoje)["01/01"] == "2027-01-01"
    assert por_data("31/02", hoje) == {}


# ------------------------------------------------------------ perguntas
def test_perguntas_de_intencao():
    p = pi.pergunta_principal(INTENTS)
    assert set(p.criterios) == {"cartoes", "falar_paulo", pi.NENHUMA}
    assert p.criterios["cartoes"]["examples"] == ["quero cartões"]
    multi = pi.perguntas_multi(INTENTS)
    assert set(multi) == {"intencao::cartoes", "intencao::falar_paulo"}
    muitas = [IntentDef(f"i{n}", grupo=f"g{n % 3}") for n in range(250)]
    assert pi.precisa_de_dois_estagios(muitas)
    grupos = pi.grupos(muitas)
    assert set(grupos) == {"g0", "g1", "g2"}
    assert pi.NENHUMA in pi.pergunta_grupo(grupos).criterios


def test_perguntas_de_entidade_transferencia_e_trecho():
    ent = EntidadeDef(
        "acabamento", "tipo de acabamento", "varios", ("verniz", "laminação")
    )
    assert set(pe.perguntas_varios(ent)) == {
        "entidade::acabamento::0",
        "entidade::acabamento::1",
    }
    assert pe.NENHUM in pe.pergunta_escolha(ent, ["a"]).criterios
    assert isinstance(pe.pergunta_presenca(ent), PerguntaNoul)
    assert isinstance(pe.pergunta_conferencia("x", "y"), PerguntaNoul)
    setor = pt.pergunta_setor([Fluxo("Comercial - vendas", "1")])
    assert isinstance(setor, PerguntaChoice) and pt.NENHUM_SETOR in setor.criterios
    regra = RegraTransferencia(
        id=3, nome="Fechar", condicao="quer fechar", exemplos_sim=["pode fechar"]
    )
    assert pt.pergunta_regra(regra).sim == ["pode fechar"]
    assert pt.pergunta_regra(regra).nao is None
    assert set(ptr.perguntas_do_trecho()) == {
        "relevante",
        "responde",
        "contradiz",
        "instrui",
    }
    assert set(pc.perguntas_da_resposta()) == {
        pc.RESPOSTA_APOIADA,
        pc.PROMETE,
        pc.RESPOSTA_TRANSFERE,
    }
    assert pt.id_campo("qtd") == "campo_presente::qtd"


def test_estado_curto_e_sem_lixo():
    hist = [
        ("human", "oi"),
        ("ai", "olá"),
        ("human", ""),
        ("human", "a"),
        ("ai", "b"),
        ("human", "c"),
    ]
    assert historico_curto(hist) == ["cliente: a", "atendente: b", "cliente: c"]
    estado = estado_da_mensagem("quero", hist, "\n\nAcme LTDA\nsegunda linha")
    assert estado["empresa"] == "Acme LTDA"
    assert "empresa" not in estado_da_mensagem("x", [], "")


# ------------------------------------------------------------- análise
def test_intencoes_por_escala_e_faixa_de_duvida():
    r = resposta(
        escolhas={pi.PRINCIPAL: ("cartoes", 0.9)},
        nouls={"intencao::falar_paulo": 0.5},
    )
    aceitas, principal, conf, revisar = decidir_intencoes(r, INTENTS, L)
    assert principal == "cartoes" and conf == 0.9
    assert [a.tipo for a in aceitas] == ["cartoes"]
    assert revisar == ["falar_paulo"]


def test_principal_abaixo_do_piso_ou_nenhuma_nao_entra():
    r = resposta(
        escolhas={pi.PRINCIPAL: ("cartoes", 0.3)}, nouls={"intencao::falar_paulo": 0.95}
    )
    aceitas, principal, _, _ = decidir_intencoes(r, INTENTS, L)
    assert principal == "" and [a.tipo for a in aceitas] == ["falar_paulo"]
    r2 = resposta(escolhas={pi.PRINCIPAL: (pi.NENHUMA, 0.99)})
    assert decidir_intencoes(r2, INTENTS, L)[1] == ""


def test_entidades_por_estrategia():
    ents = (
        EntidadeDef("qtd", estrategia="regex"),
        EntidadeDef("prazo", estrategia="data"),
        EntidadeDef("acab", estrategia="varios", opcoes=("verniz", "laminação")),
        EntidadeDef("local", estrategia="livre"),
        EntidadeDef("ausente", estrategia="lista"),
    )
    r = resposta(
        escolhas={"entidade::qtd": ("500", 0.9), "entidade::prazo": ("05/10", 0.8)},
        nouls={
            "entidade_presente::qtd": 0.9,
            "entidade_presente::prazo": 0.9,
            "entidade_presente::acab": 0.9,
            "entidade::acab::1": 0.85,
            "entidade_presente::local": 0.9,
            "entidade_presente::ausente": 0.1,
        },
    )
    conf = resposta(nouls={"confere::local": 0.95})
    achadas = decidir_entidades(
        r,
        "500 cartões para 05/10 com laminação, entregar na Rua A",
        ents,
        {"05/10": "2026-10-05"},
        conf,
        {"local": "Rua A"},
        L,
    )
    valores = {(a.tipo, a.valor) for a in achadas}
    assert ("qtd", "500") in valores
    assert ("prazo", "2026-10-05") in valores
    assert ("acab", "laminação") in valores
    assert ("local", "Rua A") in valores
    assert not any(a.tipo == "ausente" for a in achadas)


def test_valor_livre_fora_do_texto_nao_entra():
    ents = (EntidadeDef("local", estrategia="livre"),)
    r = resposta(nouls={"entidade_presente::local": 0.9})
    conf = resposta(nouls={"confere::local": 0.99})
    assert (
        decidir_entidades(r, "sem endereço", ents, {}, conf, {"local": "Rua B"}, L)
        == []
    )
    assert decidir_entidades(r, "Rua B", ents, {}, None, {"local": "Rua B"}, L) == []


def test_nota_escrita_vence_o_modelo():
    assert nota_escrita("dou nota 4") == 4
    assert nota_escrita("10 de 10") is None
    assert nota_escrita("nota 10") == 5
    assert nota_escrita("sem número") is None
    r = resposta(
        niveis={"nota": (3.4, {3: 0.6, 4: 0.4})},
        escolhas={"sentimento": ("positivo", 0.9)},
    )
    assert nota_e_sentimento(r, "") == (4, "positivo")
    assert nota_e_sentimento(r, "nota 2")[0] == 2
    assert nota_e_sentimento(resposta(), "") == (3, "negativo")
    assert Nivel(1.0, 0.5, {}).mais_provavel() == 1


# --------------------------------------------------------- transferência
FLUXOS = (Fluxo("Comercial - vendas", "10"), Fluxo("Financeiro - boletos", "20"))
REGRA_COND = RegraTransferencia(
    id=1,
    nome="Fechar pedido",
    condicao="quer fechar",
    destino_tipo="fluxo",
    destino_fluxo_id=20,
)
REGRA_INT = RegraTransferencia(
    id=2, nome="Campanha", gatilho_tipo="intencao", intencao_tag="cartoes"
)
REGRA_COLETA = RegraTransferencia(
    id=3,
    nome="Produto",
    condicao="quer orçamento",
    momento="apos_coleta",
    campos_coleta=["qtd"],
)


def _antes(r, regras=(), coletados=None, trechos=(), sinais=None):
    return decidir_antes(
        r,
        regras=regras,
        campos_coletados=coletados or set(),
        trechos=trechos,
        limiares=L,
        sinais_cfg=sinais or sinais_de(None),
    )


def test_regra_de_condicao_vence_e_tem_destino():
    r = resposta(nouls={"regra::1": 0.95, pt.PEDE_HUMANO: 0.95})
    d = _antes(r, [REGRA_COND])
    assert d.transferir and d.motivo == "regra:Fechar pedido" and d.regra == REGRA_COND
    assert escolher_destino(d.regra, r, FLUXOS, None, L) == "Financeiro - boletos"


def test_regra_de_intencao_e_apos_coleta():
    r = resposta(escolhas={pi.PRINCIPAL: ("cartoes", 0.9)})
    assert _antes(r, [REGRA_INT]).motivo == "regra:Campanha"
    r2 = resposta(nouls={"regra::3": 0.95})
    assert not _antes(r2, [REGRA_COLETA]).transferir
    assert _antes(r2, [REGRA_COLETA], coletados={"qtd"}).transferir


def test_pede_humano_duvida_e_irritacao():
    assert _antes(resposta(nouls={pt.PEDE_HUMANO: 0.9})).motivo == "pede_humano"
    assert _antes(resposta(nouls={pt.PEDE_HUMANO: 0.5})).motivo == "duvida:pede_humano"
    sem_duvida = sinais_de({"duvida_transfere": False})
    assert not _antes(
        resposta(nouls={pt.PEDE_HUMANO: 0.5}), sinais=sem_duvida
    ).transferir
    irritado = resposta(niveis={pt.INSATISFACAO: (1.8, {2: 0.8})})
    assert _antes(irritado).motivo == "irritacao"
    assert not _antes(irritado, sinais=sinais_de({"irritacao": False})).transferir
    duvida_regra = resposta(nouls={"regra::1": 0.5})
    assert _antes(duvida_regra, [REGRA_COND]).motivo == "duvida:regra:Fechar pedido"


def test_base_sem_resposta_nao_transfere_por_padrao():
    r = resposta(nouls={pt.PEDE_INFORMACAO: 0.9})
    d = _antes(r, trechos=(TrechoAvaliado("1", False, False),))
    assert d.sem_info and not d.transferir
    ligado = sinais_de({"base_sem_resposta": True})
    assert _antes(r, sinais=ligado).motivo == "base_sem_resposta"
    com_base = _antes(r, trechos=(TrechoAvaliado("1", True, False),))
    assert not com_base.sem_info


def test_campos_presentes():
    r = resposta(nouls={"campo_presente::qtd": 0.9, "campo_presente::cor": 0.2})
    assert _antes(r).campos_presentes == ("qtd",)


def test_destino_setor_padrao_e_ultimos_recursos():
    setor = resposta(escolhas={pt.SETOR: ("Comercial - vendas", 0.9)})
    assert escolher_destino(None, setor, FLUXOS, 20, L) == "Comercial - vendas"
    fraco = resposta(escolhas={pt.SETOR: ("Comercial - vendas", 0.2)})
    assert escolher_destino(None, fraco, FLUXOS, 20, L) == "Financeiro - boletos"
    assert escolher_destino(None, fraco, FLUXOS, None, L) == "Comercial - vendas"
    assert escolher_destino(None, resposta(), FLUXOS, None, L) == "Comercial - vendas"
    assert escolher_destino(None, resposta(), (), None, L) == ""


def test_trechos_aprovado_conflito_e_instrucao():
    t = [Trecho("a", "x"), Trecho("b", "y"), Trecho("c", "z")]
    avaliados = avaliar_trechos(
        [
            (t[0], resposta(nouls={"relevante": 0.9, "responde": 0.9})),
            (t[1], resposta(nouls={"relevante": 0.9, "contradiz": 0.9})),
            (t[2], resposta(nouls={"relevante": 0.9, "responde": 0.9, "instrui": 0.9})),
        ],
        L,
    )
    assert avaliados == [
        TrechoAvaliado("a", True, False),
        TrechoAvaliado("b", False, True),
        TrechoAvaliado("c", False, False),
    ]


def test_comportamento_da_intencao():
    intents = (IntentDef("cartoes", comportamento="colete tipo e quantidade"),)
    assert (
        comportamento_da_intencao("cartoes", 0.9, intents, L)
        == "colete tipo e quantidade"
    )
    assert comportamento_da_intencao("cartoes", 0.1, intents, L) == ""
    assert comportamento_da_intencao("outra", 0.9, intents, L) == ""


def _depois(nouls, sinais=None, piso=None, ja=False):
    return decidir_depois(
        resposta(nouls=nouls),
        limiares=L,
        sinais_cfg=sinais or sinais_de(None),
        piso_b4=piso,
        ja_regerada=ja,
    )


def test_depois_da_geracao():
    ok = _depois({pc.RESPOSTA_APOIADA: 0.9})
    assert not (ok.transferir or ok.sem_info or ok.a_revisar or ok.regerar)
    assert (
        _depois({pc.RESPOSTA_APOIADA: 0.9, pc.PROMETE: 0.9}).motivo
        == "promete_o_que_nao_pode"
    )
    assert _depois({pc.RESPOSTA_APOIADA: 0.9, pc.RESPOSTA_TRANSFERE: 0.9}).regerar
    assert _depois(
        {pc.RESPOSTA_APOIADA: 0.9, pc.RESPOSTA_TRANSFERE: 0.9}, ja=True
    ).a_revisar
    assert _depois({pc.RESPOSTA_APOIADA: 0.1}).sem_info
    assert _depois({pc.RESPOSTA_APOIADA: 0.5}).a_revisar
    ligado = sinais_de({"resposta_sem_apoio": True})
    assert (
        _depois({pc.RESPOSTA_APOIADA: 0.5}, sinais=ligado).motivo
        == "resposta_sem_apoio"
    )
    assert _depois({pc.RESPOSTA_APOIADA: 0.85}, sinais=ligado, piso=0.9).transferir


def test_uso_soma_requisicoes():
    uso = Uso.de([resposta(tokens=10), resposta(tokens=5)])
    assert (
        uso.tokens_entrada == 15 and uso.requisicoes == 2 and uso.modelo == "jev-1.13.0"
    )
