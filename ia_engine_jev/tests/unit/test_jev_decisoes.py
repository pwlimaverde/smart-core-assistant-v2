"""Leitura, ato, evidência, conferência, limiares, candidatos e perguntas do
motor Jev — funções puras."""

from __future__ import annotations

from datetime import UTC, date, datetime
from types import SimpleNamespace

from ia_engine_jev.candidatos import esta_no_texto, por_data, por_lista, por_regex
from ia_engine_jev.config.models import RegraTransferencia
from ia_engine_jev.conversao import (
    dados_da_coleta,
    intents_do_proto,
    politica_da_config,
)
from ia_engine_jev.decisoes.analise import decidir_entidades, decidir_intencoes
from ia_engine_jev.decisoes.ato import (
    Plano,
    aplicar_evidencia,
    fora_do_horario,
    planejar,
    texto_da_transferencia,
)
from ia_engine_jev.decisoes.conferencia import (
    PROBLEMA_ECOA,
    PROBLEMA_PERGUNTAS,
    PROBLEMA_PROIBIDO,
    PROBLEMA_PROMETE,
    PROBLEMA_SEM_APOIO,
    PROBLEMA_TRANSFERE,
    conferir,
    contar_perguntas,
    desfecho,
)
from ia_engine_jev.decisoes.leitura import Leitura, interpretar
from ia_engine_jev.decisoes.limiares import Limiares, limiares_de, sinais_de
from ia_engine_jev.decisoes.transferencia import (
    avaliar_trechos,
    decidir_transferencia,
    escolher_destino,
    evidencia_ordenada,
)
from ia_engine_jev.domain.jev import (
    Dado,
    EntidadeDef,
    Fluxo,
    Horario,
    IntentDef,
    Politica,
    Trecho,
    TrechoAvaliado,
)
from ia_engine_jev.perguntas import conferencia as pc
from ia_engine_jev.perguntas import conversa as pv
from ia_engine_jev.perguntas import entidades as pe
from ia_engine_jev.perguntas import intencoes as pi
from ia_engine_jev.perguntas import transferencia as pt
from ia_engine_jev.perguntas import trechos as ptr
from ia_engine_jev.perguntas.comum import estado_da_mensagem, historico_curto
from ia_engine_jev.perguntas.leitura import PedidoDeLeitura, montar_leitura
from ia_engine_jev.typesafe import Nivel, PerguntaChoice, PerguntaNoul, Uso
from tests.conftest import runtime_config
from tests.jev_fakes import resposta

PANFLETO = IntentDef(
    "panfletos",
    "offset",
    "Pedido de panfletos",
    "quero panfletos",
    "Colete o essencial e passe para o Paulo.",
    campos_coleta=("formato", "quantidade", "arte"),
    max_perguntas=2,
)
CARTAO = IntentDef("cartoes", "offset", "Cartões de visita", "quero cartões")
SAUDACAO = IntentDef("saudacao", "basico", "Cumprimento", "oi")
INTENTS = (PANFLETO, CARTAO, SAUDACAO)
DADOS = {
    "formato": Dado("formato", "formato", "tamanho do panfleto"),
    "quantidade": Dado("quantidade", "quantidade", "tiragem"),
    "arte": Dado("arte", "arte", "se já tem a arte"),
}
L = Limiares()
SINAIS = sinais_de(None)


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
    assert por_data("dia 01/01", hoje)["01/01"] == "2027-01-01"
    assert por_data("31/02", hoje) == {}


# ------------------------------------------------------------ perguntas
def test_perguntas_de_intencao():
    p = pi.pergunta_principal(INTENTS)
    assert set(p.criterios) == {"panfletos", "cartoes", "saudacao", pi.NENHUMA}
    assert p.criterios["cartoes"]["examples"] == ["quero cartões"]
    assert set(pi.perguntas_multi(INTENTS)) == {
        "intencao::panfletos",
        "intencao::cartoes",
        "intencao::saudacao",
    }
    muitas = [IntentDef(f"i{n}", grupo=f"g{n % 3}") for n in range(250)]
    assert pi.precisa_de_dois_estagios(muitas)
    grupos = pi.grupos(muitas)
    assert set(grupos) == {"g0", "g1", "g2"}
    assert pi.NENHUMA in pi.pergunta_grupo(grupos).criterios


def test_perguntas_de_entidade_transferencia_e_trecho():
    ent = EntidadeDef("acabamento", "tipo de acabamento", "varios", ("verniz", "lam"))
    assert set(pe.perguntas_varios(ent)) == {
        "entidade::acabamento::0",
        "entidade::acabamento::1",
    }
    assert pe.NENHUM in pe.pergunta_escolha(ent, ["a"]).criterios
    assert isinstance(pe.pergunta_presenca(ent), PerguntaNoul)
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
    assert pt.id_campo("qtd") == "campo_presente::qtd"


def test_perguntas_da_conferencia():
    base = pc.perguntas_da_resposta()
    assert set(base) == {
        pc.RESPOSTA_APOIADA,
        pc.PROMETE,
        pc.RESPOSTA_TRANSFERE,
        pc.ECOA,
    }
    completa = pc.perguntas_da_resposta(
        nunca_pedir=["telefone"], valores={"campo_qtd": ("quantidade", "tiragem")}
    )
    assert pc.PEDE_PROIBIDO in completa and "confere::campo_qtd" in completa
    so_valores = pc.perguntas_da_resposta(com_texto=False, valores={"x": ("x", "")})
    assert set(so_valores) == {"confere::x"}
    estado = pc.estado_da_resposta("p", "r", ["e"], "sem desconto", {"x": "1"})
    assert estado["valores"] == {"x": "1"} and "restricoes_da_persona" in estado
    assert "valores" not in pc.estado_da_resposta("p", "r", [], "")


def test_perguntas_da_conversa():
    assert isinstance(pv.pergunta_tom().niveis, tuple)
    assert pv.pergunta_nao_fornecido(["ACM"]).instrucoes["not_offered"] == ["ACM"]
    assert pv.pergunta_conhecido(DADOS["arte"]).instrucoes["field"] == "arte"
    assert isinstance(pv.pergunta_instrui_bot(), PerguntaNoul)
    assert pv.nota_do_tom(None) == (0, "")
    assert pv.nota_do_tom(Nivel(0.2, 0.9, {0: 0.8, 1: 0.2})) == (1, "negativo")
    assert pv.nota_do_tom(Nivel(2.0, 0.9, {2: 0.9})) == (3, "neutro")
    assert pv.nota_do_tom(Nivel(4.0, 0.9, {4: 0.9})) == (5, "positivo")
    assert pv.irritacao_do_tom(None) == 0.0
    assert pv.irritacao_do_tom(Nivel(0.0, 0.9, {})) == 2.0
    assert pv.irritacao_do_tom(Nivel(3.5, 0.9, {})) == 0.0


def test_estado_curto_e_sem_lixo():
    hist = [("human", str(n)) for n in range(8)] + [("human", "")]
    assert historico_curto(hist) == [f"cliente: {n}" for n in range(3, 8)]
    estado = estado_da_mensagem("quero", [], "\n\nAcme LTDA\nsegunda linha")
    assert estado["empresa"] == "Acme LTDA"
    assert "empresa" not in estado_da_mensagem("x", [], "")


def test_montagem_da_leitura_simples_e_completa():
    ents = (
        EntidadeDef("qtd", estrategia="regex"),
        EntidadeDef("prazo", estrategia="data"),
        EntidadeDef("tipo", estrategia="lista", opcoes=("banner",)),
        EntidadeDef("acab", estrategia="varios", opcoes=("verniz",)),
    )
    simples = montar_leitura(
        PedidoDeLeitura(
            mensagem="500 banners para 05/10",
            historico=(),
            intents=INTENTS,
            entidades=ents,
            hoje=date(2026, 9, 28),
        )
    )
    assert pv.TOM in simples.perguntas and pi.PRINCIPAL in simples.perguntas
    assert pt.PEDE_HUMANO not in simples.perguntas
    assert (
        "entidade::qtd" in simples.perguntas and "entidade::tipo" in simples.perguntas
    )
    assert simples.datas["05/10"] == "2026-10-05"
    completa = montar_leitura(
        PedidoDeLeitura(
            mensagem="oi",
            historico=(),
            intents=INTENTS,
            completa=True,
            regras=(RegraTransferencia(id=1, nome="x", condicao="y"),),
            fluxos=(Fluxo("Comercial - vendas", "1"),),
            dados_coleta=tuple(DADOS.values()),
            ja_coletados=frozenset({"arte"}),
            campos_pendentes=(("cor", "cor", "cor da impressão"),),
            politica=Politica(nao_fornecemos=("ACM",)),
        )
    )
    ids = set(completa.perguntas)
    assert {pt.PEDE_HUMANO, pt.PEDE_INFORMACAO, pv.INSTRUI, pt.SETOR} <= ids
    assert {"regra::1", "campo_presente::cor", pv.NAO_FORNECIDO} <= ids
    assert {"conhecido::formato", "conhecido::quantidade"} <= ids
    assert "conhecido::arte" not in ids  # já está no cartão
    muitas = tuple(IntentDef(f"i{n}", grupo=f"g{n % 3}") for n in range(250))
    dois = montar_leitura(PedidoDeLeitura(mensagem="x", historico=(), intents=muitas))
    assert dois.por_grupo is not None and pi.GRUPO in dois.perguntas


# ------------------------------------------------------------- análise
def test_intencoes_por_escala_e_faixa_de_duvida():
    r = resposta(
        escolhas={pi.PRINCIPAL: ("cartoes", 0.9)},
        nouls={"intencao::saudacao": 0.5},
    )
    aceitas, principal, conf, revisar = decidir_intencoes(r, INTENTS, L)
    assert principal == "cartoes" and conf == 0.9
    assert [a.tipo for a in aceitas] == ["cartoes"]
    assert revisar == ["saudacao"]


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
    assert {("qtd", "500"), ("prazo", "2026-10-05"), ("acab", "laminação")} <= valores
    assert ("local", "Rua A") in valores
    assert not any(a.tipo == "ausente" for a in achadas)


def test_interpretar_leitura_com_tom_coleta_e_campos():
    r = resposta(
        escolhas={pi.PRINCIPAL: ("panfletos", 0.9)},
        nouls={
            pt.PEDE_HUMANO: 0.1,
            "conhecido::formato": 0.9,
            "conhecido::quantidade": 0.2,
            "campo_presente::cor": 0.95,
        },
        niveis={pv.TOM: (0.4, {0: 0.7, 1: 0.3})},
    )
    leitura = interpretar(
        r,
        intents=INTENTS,
        limiares=L,
        dados_coleta=tuple(DADOS.values()),
        ja_coletados=frozenset({"arte"}),
    )
    assert leitura.efetiva == PANFLETO and not leitura.efetiva_pelo_grupo
    assert leitura.conhecidos == frozenset({"formato", "arte"})
    assert leitura.campos_presentes == ("cor",)
    assert (leitura.tom_nota, leitura.tom_rotulo) == (1, "negativo")
    assert leitura.irritacao > 1.5


def test_intencao_incerta_usa_o_grupo():
    probs = {"panfletos": 0.45, "cartoes": 0.4, "saudacao": 0.15}
    r = resposta(escolhas={pi.PRINCIPAL: ("panfletos", 0.4, probs)})
    leitura = interpretar(r, intents=INTENTS, limiares=L)
    assert leitura.principal == ""  # não vira assunto nem etiqueta
    assert leitura.efetiva == PANFLETO and leitura.efetiva_pelo_grupo
    espalhado = resposta(
        escolhas={
            pi.PRINCIPAL: ("panfletos", 0.3, {"panfletos": 0.35, "saudacao": 0.4})
        }
    )
    assert interpretar(espalhado, intents=INTENTS, limiares=L).efetiva is None
    assert interpretar(resposta(), intents=INTENTS, limiares=L).efetiva is None


# --------------------------------------------------------- transferência
FLUXOS = (Fluxo("Comercial - vendas", "10"), Fluxo("Financeiro - boletos", "20"))
REGRA_COND = RegraTransferencia(
    id=1, nome="Fechar pedido", condicao="quer fechar", destino_tipo="fluxo",
    destino_fluxo_id=20,
)  # fmt: skip
REGRA_INT = RegraTransferencia(
    id=2, nome="Status", gatilho_tipo="intencao", intencao_tag="cartoes"
)
REGRA_COLETA = RegraTransferencia(
    id=3, nome="Produto", condicao="quer orçamento", momento="apos_coleta",
    campos_coleta=["qtd"],
)  # fmt: skip


def _ler(r, **kw) -> Leitura:
    return interpretar(r, intents=INTENTS, limiares=L, **kw)


def _transf(r, regras=(), coletados=frozenset(), sinais=None):
    return decidir_transferencia(
        _ler(r),
        regras=regras,
        campos_coletados=coletados,
        limiares=L,
        sinais_cfg=sinais or SINAIS,
    )


def test_regra_de_condicao_vence_e_tem_destino():
    r = resposta(nouls={"regra::1": 0.95, pt.PEDE_HUMANO: 0.95})
    d = _transf(r, [REGRA_COND])
    assert d.transferir and d.motivo == "regra:Fechar pedido" and d.regra == REGRA_COND
    assert escolher_destino(d.regra, r, FLUXOS, None, L) == "Financeiro - boletos"


def test_regra_de_intencao_e_apos_coleta():
    r = resposta(escolhas={pi.PRINCIPAL: ("cartoes", 0.9)})
    assert _transf(r, [REGRA_INT]).motivo == "regra:Status"
    r2 = resposta(nouls={"regra::3": 0.95})
    assert not _transf(r2, [REGRA_COLETA]).transferir
    assert _transf(r2, [REGRA_COLETA], coletados=frozenset({"qtd"})).transferir


def test_pede_humano_duvida_e_irritacao():
    assert _transf(resposta(nouls={pt.PEDE_HUMANO: 0.9})).motivo == "pede_humano"
    assert _transf(resposta(nouls={pt.PEDE_HUMANO: 0.5})).motivo == "duvida:pede_humano"
    sem_duvida = sinais_de({"duvida_transfere": False})
    assert not _transf(
        resposta(nouls={pt.PEDE_HUMANO: 0.5}), sinais=sem_duvida
    ).transferir
    irritado = resposta(niveis={pv.TOM: (0.1, {0: 0.9})})
    assert _transf(irritado).motivo == "irritacao"
    assert not _transf(irritado, sinais=sinais_de({"irritacao": False})).transferir
    duvida_regra = resposta(nouls={"regra::1": 0.5})
    assert _transf(duvida_regra, [REGRA_COND]).motivo == "duvida:regra:Fechar pedido"


def test_destino_setor_padrao_e_ultimos_recursos():
    setor = resposta(escolhas={pt.SETOR: ("Comercial - vendas", 0.9)})
    # O padrão do tenant vence o setor do Jev.
    assert escolher_destino(None, setor, FLUXOS, 20, L) == "Financeiro - boletos"
    assert escolher_destino(None, setor, FLUXOS, None, L) == "Comercial - vendas"
    fraco = resposta(escolhas={pt.SETOR: ("Financeiro - boletos", 0.2)})
    assert escolher_destino(None, fraco, FLUXOS, 99, L) == "Financeiro - boletos"
    assert escolher_destino(None, fraco, FLUXOS, None, L) == "Financeiro - boletos"
    assert escolher_destino(None, resposta(), FLUXOS, None, L) == "Comercial - vendas"
    assert escolher_destino(None, resposta(), (), None, L) == ""


def test_trechos_conflito_antes_de_evidencia_e_confiaveis():
    t = [Trecho("a", "x"), Trecho("b", "y"), Trecho("c", "z"), Trecho("empresa", "e")]
    tudo = {"relevante": 0.9, "responde": 0.9, "instrui": 0.9}
    avaliados = avaliar_trechos(
        [
            (t[0], resposta(nouls={"relevante": 0.9, "responde": 0.7})),
            (
                t[1],
                resposta(nouls={"relevante": 0.9, "responde": 0.9, "contradiz": 0.9}),
            ),
            (t[2], resposta(nouls=tudo)),
            (t[3], resposta(nouls=tudo)),
        ],
        L,
        frozenset({"empresa"}),
    )
    assert [(a.id, a.aprovado, a.conflito) for a in avaliados] == [
        ("a", True, False),
        ("b", False, True),
        ("c", False, False),
        ("empresa", True, False),
    ]
    evid, conflito = evidencia_ordenada(t, avaliados, 3, frozenset({"empresa"}))
    assert evid == ["x"] and conflito == ["y"]


def test_evidencia_reordenada_pelo_jev():
    t = [Trecho("1", "um"), Trecho("2", "dois"), Trecho("3", "tres")]
    avaliados = [
        TrechoAvaliado("1", True, False, 0.6),
        TrechoAvaliado("2", True, False, 0.95),
        TrechoAvaliado("3", True, False, 0.8),
    ]
    assert evidencia_ordenada(t, avaliados, 2)[0] == ["dois", "tres"]


# ------------------------------------------------------------------ ato
def _plano(r, *, rodadas=0, politica=None, regras=(), sinais=None, **kw) -> Plano:
    return planejar(
        _ler(r, dados_coleta=tuple(DADOS.values()), **kw),
        regras=regras,
        campos_coletados=frozenset(),
        rodadas_coleta=rodadas,
        dados=DADOS,
        politica=politica or Politica(),
        limiares=L,
        sinais_cfg=sinais or SINAIS,
    )


def test_guarda_de_entrada_barra_antes_de_tudo():
    r = resposta(nouls={pv.INSTRUI: 0.95, pt.PEDE_HUMANO: 0.99})
    p = _plano(r)
    assert p.ato == "barrada" and p.motivo == "instrui_bot" and not p.usa_llm


def test_transferencia_antes_do_resto():
    p = _plano(resposta(nouls={pt.PEDE_HUMANO: 0.95}))
    assert p.ato == "transferir" and p.transferir and p.motivo == "pede_humano"


def test_nao_fornecido_transfere_com_alternativa_ou_vira_nota():
    pol = Politica(nao_fornecemos=("ACM",), alternativa="Fazemos placa em PVC.")
    r = resposta(nouls={pv.NAO_FORNECIDO: 0.9})
    p = _plano(r, politica=pol)
    assert p.ato == "transferir" and p.prefixo == "Fazemos placa em PVC."
    so_nota = Politica(
        nao_fornecemos=("ACM",), alternativa="PVC", transferir_nao_fornecido=False
    )
    p2 = _plano(r, politica=so_nota)
    assert p2.ato == "responder" and p2.nota_politica == "PVC"
    assert p2.precisa_evidencia


def test_coleta_pede_o_que_falta_uma_rodada_so():
    r = resposta(
        escolhas={pi.PRINCIPAL: ("panfletos", 0.9)},
        nouls={"conhecido::formato": 0.9},
    )
    p = _plano(r)
    assert p.ato == "coletar"
    assert [d.id for d in p.perguntar] == ["quantidade", "arte"]
    assert p.comportamento.startswith("Colete")
    # Rodada feita: transfere, mesmo faltando dado.
    assert _plano(r, rodadas=1).motivo == "coleta_concluida"
    # Nada falta: transfere na hora.
    tudo = resposta(
        escolhas={pi.PRINCIPAL: ("panfletos", 0.9)},
        nouls={f"conhecido::{d}": 0.9 for d in DADOS},
    )
    assert _plano(tudo).ato == "transferir"


def test_coleta_com_continuar_e_pedido_de_informacao():
    continua = IntentDef("p", campos_coleta=("formato",), apos_coleta="continuar")
    r = resposta(escolhas={pi.PRINCIPAL: ("p", 0.9)})
    p = planejar(
        interpretar(r, intents=(continua,), limiares=L),
        regras=(),
        campos_coletados=frozenset(),
        rodadas_coleta=1,
        dados=DADOS,
        politica=Politica(),
        limiares=L,
        sinais_cfg=SINAIS,
    )
    assert p.ato == "social"
    info = resposta(
        escolhas={pi.PRINCIPAL: ("panfletos", 0.9)},
        nouls={pt.PEDE_INFORMACAO: 0.9},
    )
    pi_ = _plano(info)
    assert pi_.ato == "responder" and pi_.precisa_evidencia and len(pi_.perguntar) == 2


def test_social_quando_nada_mais_se_aplica():
    p = _plano(resposta(escolhas={pi.PRINCIPAL: ("saudacao", 0.95)}))
    assert p.ato == "social" and p.usa_llm and not p.perguntar


def test_evidencia_fecha_o_responder():
    info = _plano(resposta(nouls={pt.PEDE_INFORMACAO: 0.9}))
    com = aplicar_evidencia(info, [TrechoAvaliado("1", True, False)], sinais_cfg=SINAIS)
    assert com.ato == "responder"
    sem = aplicar_evidencia(
        info, [TrechoAvaliado("1", False, False)], sinais_cfg=SINAIS
    )
    assert sem.ato == "sem_info" and sem.motivo == "base_sem_resposta"
    ligado = sinais_de({"base_sem_resposta": True})
    assert aplicar_evidencia(info, [], sinais_cfg=ligado).ato == "transferir"
    conflito = aplicar_evidencia(
        info, [TrechoAvaliado("1", False, True)], sinais_cfg=SINAIS
    )
    assert conflito.ato == "responder"
    com_coleta = _plano(
        resposta(
            escolhas={pi.PRINCIPAL: ("panfletos", 0.9)},
            nouls={pt.PEDE_INFORMACAO: 0.9},
        )
    )
    assert aplicar_evidencia(com_coleta, [], sinais_cfg=SINAIS).ato == "coletar"
    social = _plano(resposta())
    assert aplicar_evidencia(social, [], sinais_cfg=SINAIS) is social


def test_horario_e_texto_da_transferencia():
    h = Horario(
        fuso="America/Fortaleza",
        dias=(0, 1, 2, 3, 4),
        inicio_min=480,
        fim_min=1020,
        aviso="Amanhã.",
    )
    segunda_10h = datetime(2026, 9, 28, 13, 0, tzinfo=UTC)  # 10h em Fortaleza
    segunda_20h = datetime(2026, 9, 28, 23, 0, tzinfo=UTC)
    domingo = datetime(2026, 9, 27, 13, 0, tzinfo=UTC)
    assert not fora_do_horario(segunda_10h, h)
    assert fora_do_horario(segunda_20h, h) and fora_do_horario(domingo, h)
    assert not fora_do_horario(segunda_20h, None)
    assert not fora_do_horario(segunda_20h, Horario(fuso="Nao/Existe"))
    regra = RegraTransferencia(id=1, nome="x", mensagem="Vou chamar o Paulo.")
    t = texto_da_transferencia(
        Plano("transferir", regra=regra, prefixo="Não fazemos ACM."),
        msg_transferencia="padrão",
        msg_sem_info="sem info",
        aviso_fora_do_horario="Amanhã.",
    )
    assert t == "Não fazemos ACM.\n\nVou chamar o Paulo.\n\nAmanhã."
    base = texto_da_transferencia(
        Plano("transferir", motivo="base_sem_resposta"),
        msg_transferencia="padrão",
        msg_sem_info="sem info",
    )
    assert base == "sem info\n\npadrão"


# ----------------------------------------------------------- conferência
def test_conferir_e_desfecho():
    ok = conferir(
        resposta(nouls={pc.RESPOSTA_APOIADA: 0.9}),
        texto="Temos sim. Qual o formato?",
        exige_apoio=True,
        limite_perguntas=1,
        limiares=L,
    )
    assert ok.problemas == ()
    assert desfecho(ok, ja_escalada=False, limiares=L, sinais_cfg=SINAIS) == "enviar"
    ruim = conferir(
        resposta(
            nouls={
                pc.RESPOSTA_APOIADA: 0.3,
                pc.PROMETE: 0.9,
                pc.RESPOSTA_TRANSFERE: 0.9,
                pc.ECOA: 0.9,
                pc.PEDE_PROIBIDO: 0.9,
            }
        ),
        texto="Qual? Quando? Onde?",
        exige_apoio=True,
        limite_perguntas=2,
        limiares=L,
    )
    assert set(ruim.problemas) == {
        PROBLEMA_PROMETE,
        PROBLEMA_TRANSFERE,
        PROBLEMA_ECOA,
        PROBLEMA_PROIBIDO,
        PROBLEMA_SEM_APOIO,
        PROBLEMA_PERGUNTAS,
    }
    assert desfecho(ruim, ja_escalada=False, limiares=L, sinais_cfg=SINAIS) == "escalar"
    assert desfecho(ruim, ja_escalada=True, limiares=L, sinais_cfg=SINAIS) == "sem_info"
    ligado = sinais_de({"resposta_sem_apoio": True})
    assert (
        desfecho(ruim, ja_escalada=True, limiares=L, sinais_cfg=ligado) == "transferir"
    )
    estilo = conferir(
        resposta(nouls={pc.ECOA: 0.95}),
        texto="ok",
        exige_apoio=False,
        limite_perguntas=1,
        limiares=L,
    )
    assert (
        desfecho(estilo, ja_escalada=True, limiares=L, sinais_cfg=SINAIS) == "a_revisar"
    )
    sem_exigir = conferir(
        resposta(nouls={pc.RESPOSTA_APOIADA: 0.1}),
        texto="Olá!",
        exige_apoio=False,
        limite_perguntas=1,
        limiares=L,
        piso_b4=0.9,
    )
    assert sem_exigir.problemas == ()
    assert contar_perguntas("Oi?? Tudo bem? ok") == 2


# ------------------------------------------------------------ conversão
def test_intents_do_proto_com_coleta():
    proto = [
        SimpleNamespace(
            tag="p", grupo="g", descricao="d", exemplo="e", comportamento="c",
            campos_coleta=[" formato ", ""], max_perguntas=0, apos_coleta="xyz",
        ),
        SimpleNamespace(
            tag="", grupo="", descricao="", exemplo="", comportamento="",
            campos_coleta=[], max_perguntas=1, apos_coleta="continuar",
        ),
    ]  # fmt: skip
    (i,) = intents_do_proto(proto)
    assert i.campos_coleta == ("formato",)
    assert i.max_perguntas == 2 and i.apos_coleta == "transferir"


def test_dados_da_coleta_resolvem_entidade_campo_e_texto():
    intents = (
        IntentDef("a", campos_coleta=("tipo_produto", "cor", "arte pronta?")),
        IntentDef("b", campos_coleta=("tipo_produto",)),
    )
    dados = dados_da_coleta(
        intents,
        (EntidadeDef("tipo_produto", "tipo do produto"),),
        [("cor", "Cor", "cor da impressão")],
    )
    assert dados == (
        Dado("tipo_produto", "tipo_produto", "tipo do produto"),
        Dado("cor", "Cor", "cor da impressão"),
        Dado("arte pronta?", "arte pronta?", ""),
    )


def test_politica_da_config():
    vazia = politica_da_config(runtime_config())
    assert vazia == Politica()
    cfg = runtime_config(
        jev_config={
            "nao_fornecemos": {
                "itens": ["ACM", " "],
                "alternativa": "PVC",
                "transferir": False,
            },
            "nunca_pedir": ["telefone"],
            "horario": {
                "fuso": "America/Fortaleza",
                "dias": [0, 1, 9, "x"],
                "inicio": "08:00",
                "fim": "25:00",
                "aviso": "Amanhã",
            },
            "llm": {"redacao": "mini", "escalada": "grande"},
            "trechos_max": 50,
        }
    )
    p = politica_da_config(cfg)
    assert p.nao_fornecemos == ("ACM",) and p.alternativa == "PVC"
    assert not p.transferir_nao_fornecido and p.nunca_pedir == ("telefone",)
    assert p.horario is not None and p.horario.dias == (0, 1)
    assert p.horario.inicio_min == 480 and p.horario.fim_min == 18 * 60
    assert (p.modelo_redacao, p.modelo_escalada, p.trechos_max) == ("mini", "grande", 3)


def test_uso_soma_requisicoes():
    uso = Uso.de([resposta(tokens=10), resposta(tokens=5)])
    assert uso.tokens_entrada == 15 and uso.requisicoes == 2
    assert uso.modelo == "jev-1.13.0"
    assert Nivel(1.0, 0.5, {}).mais_provavel() == 1
