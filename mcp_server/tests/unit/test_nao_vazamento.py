"""O que não pode sair deste servidor.

Três regras, três testes:

* `get_tenant_config` nunca devolve chave de provedor;
* a configuração nunca imprime segredo no log de startup;
* o texto que vai ao agente não carrega dado de cliente.
"""

from __future__ import annotations

import os

os.environ.setdefault("OTEL_SDK_DISABLED", "true")

from mcp_server.grpc.contracts import admin_pb2 as pb  # noqa: E402
from mcp_server.settings import Settings  # noqa: E402
from mcp_server.tools import leitura  # noqa: E402
from tests.conftest import como  # noqa: E402
from tests.unit.test_guards import montar_ambiente  # noqa: E402


async def test_get_tenant_config_nao_devolve_chave_de_provedor():
    """A chave de um provedor não tem por que entrar no contexto de um LLM.

    Nem inteira, nem mascarada, nem truncada: um prefixo de chave ainda é
    material para um ataque, e o agente não tem uso para ele.
    """
    chave_secreta = "sk-proj-ABCDEF1234567890segredoquenaopodevazar"
    config = pb.GetTenantConfigResponse(
        dados_empresa="Loja do Zé",
        persona_bot="Atendente simpático",
        model="gpt-5",
        api_keys=[
            pb.ApiKeyEntry(key="openai", value=chave_secreta),
            pb.ApiKeyEntry(key="groq", value="gsk_outrachave"),
            # Provedor sem chave configurada não deve aparecer na lista.
            pb.ApiKeyEntry(key="anthropic", value=""),
        ],
    )
    servidor, registro, executor, _, _ = montar_ambiente({"GetMyTenantConfig": config})
    leitura.registrar(servidor, registro, executor)

    with como(["configuracoes:read"]):
        resultado = await servidor.funcoes["get_tenant_config"]()

    serializado = repr(resultado)
    assert chave_secreta not in serializado
    assert "sk-proj" not in serializado
    assert "gsk_" not in serializado
    # O que o agente precisa saber é *quais* provedores estão configurados.
    assert resultado["provedores_configurados"] == ["groq", "openai"]
    assert "anthropic" not in resultado["provedores_configurados"]


def test_resumo_de_configuracao_nao_imprime_segredo():
    cfg = Settings(
        oauth_public_key_pem="-----BEGIN PUBLIC KEY-----\nMIIB...\n",
        service_secret="segredo-de-servico-que-nao-pode-aparecer",
    )
    resumo = repr(cfg.resumo_seguro())

    assert "segredo-de-servico" not in resumo
    assert "BEGIN PUBLIC KEY" not in resumo
    # O que interessa no log é se está configurado, não o valor.
    assert "'chave_publica_configurada': True" in resumo
    assert "'segredo_de_servico_configurado': True" in resumo


def test_url_de_metadata_do_recurso_segue_a_rfc_9728():
    cfg = Settings(oauth_resource="https://mcp.smartcoreassistant.com.br/")
    assert (
        cfg.resource_metadata_url
        == "https://mcp.smartcoreassistant.com.br/.well-known/oauth-protected-resource"
    )


def test_chave_publica_normaliza_n_escapado_do_env_file():
    """O `env_file` do Compose não aceita PEM multilinha.

    Se o valor chegar com `\\n` literal e ninguém normalizar, o `cryptography`
    recusa a chave e **todo** token é rejeitado — servidor de pé que não atende
    ninguém. Este teste é a trava contra alguém "simplificar" a propriedade.
    """
    escapado = "-----BEGIN PUBLIC KEY-----\\nMIIB\\n-----END PUBLIC KEY-----\\n"
    cfg = Settings(oauth_public_key_pem=escapado)

    assert "\\n" not in cfg.chave_publica
    assert cfg.chave_publica.count("\n") == 3
    assert cfg.chave_publica.startswith("-----BEGIN PUBLIC KEY-----")


def test_chave_publica_e_noop_quando_as_quebras_ja_sao_reais():
    real = "-----BEGIN PUBLIC KEY-----\nMIIB\n-----END PUBLIC KEY-----\n"
    assert Settings(oauth_public_key_pem=real).chave_publica == real


# ---------------------------------------------------------------------------
# Sonda do container
# ---------------------------------------------------------------------------


def test_healthcheck_trata_401_como_saude(monkeypatch):
    """401 é o sinal de saúde, e não um erro.

    Parece invertido, mas é o teste mais forte disponível: um 401 com
    `WWW-Authenticate` prova que o processo está de pé, que o roteamento funciona
    e que a camada de autenticação está montada.
    """
    from mcp_server import healthcheck

    class Resposta:
        status_code = 401

    monkeypatch.setattr(healthcheck.httpx, "post", lambda *a, **k: Resposta())
    assert healthcheck.main() == 0


def test_healthcheck_trata_200_como_FALHA(monkeypatch):
    """200 sem token significa servidor aceitando requisição sem autorização.

    Isso é defeito, não saúde — e a sonda tem de derrubar o container.
    """
    from mcp_server import healthcheck

    class Resposta:
        status_code = 200

    monkeypatch.setattr(healthcheck.httpx, "post", lambda *a, **k: Resposta())
    assert healthcheck.main() == 1


def test_healthcheck_falha_quando_o_processo_nao_responde(monkeypatch):
    from mcp_server import healthcheck

    def explode(*_a, **_k):
        raise OSError("conexão recusada")

    monkeypatch.setattr(healthcheck.httpx, "post", explode)
    assert healthcheck.main() == 1


def test_chave_publica_remove_aspas_do_docker_run():
    """`docker run --env-file` mantém as aspas no valor — medido, não suposto.

    O `env_file:` do Compose as remove, então o deploy não passa por aqui. Mas
    quem depurar um container à mão usa `docker run`, e sem esta limpeza o PEM
    começaria com `"` e **todo** token seria rejeitado.
    """
    com_aspas = '"-----BEGIN PUBLIC KEY-----\\nMIIB\\n-----END PUBLIC KEY-----\\n"'
    cfg = Settings(oauth_public_key_pem=com_aspas)

    assert cfg.chave_publica.startswith("-----BEGIN PUBLIC KEY-----")
    assert '"' not in cfg.chave_publica
    assert cfg.chave_publica.count("\n") == 3
