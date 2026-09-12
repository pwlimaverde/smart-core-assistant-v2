"""O servidor montado por inteiro, com chave RSA real e o app ASGI de verdade.

O `TestClient` do Starlette 1.6 roda sobre `httpx2` — o mesmo que o SDK `mcp` já
traz —, então este arquivo não acrescenta dependência nenhuma. Vale registrar
porque a intuição diz que ele precisaria do `httpx` 0.x, e ele não precisa.

Os testes unitários exercitam as peças com dublês. Este monta o
`ServidorMcpFiltrado` como o processo monta, com uma chave gerada na hora, e bate
no app Starlette pelo cliente de teste — sem rede, sem container.

É o teste que pega o que nenhum unitário pega: o SDK montando as rotas de
descoberta, o `RequireAuthMiddleware` recusando sem token, e o filtro de
`tools/list` funcionando pelo caminho real (HTTP → middleware → contextvar).
"""

from __future__ import annotations

import os
import time

import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

os.environ.setdefault("OTEL_SDK_DISABLED", "true")

ISSUER = "https://auth.teste.local"
RESOURCE = "https://mcp.teste.local"


@pytest.fixture(scope="module")
def chaves() -> tuple[str, str]:
    chave = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    privada = chave.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode()
    publica = (
        chave.public_key()
        .public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )
        .decode()
    )
    return privada, publica


@pytest.fixture(scope="module")
def servidor(chaves):
    """Monta o servidor com a configuração vindo do ambiente, como em produção."""
    privada, publica = chaves
    for chave, valor in {
        "MCP_OAUTH_ISSUER": ISSUER,
        "MCP_OAUTH_RESOURCE": RESOURCE,
        "MCP_OAUTH_PUBLIC_KEY_PEM": publica,
        "MCP_SERVICE_SECRET": "segredo-de-teste",
    }.items():
        os.environ[chave] = valor

    from mcp_server.server import montar

    return montar()


def token(privada: str, escopos: list[str], **extra) -> str:
    agora = int(time.time())
    claims = {
        "iss": ISSUER,
        "sub": "7",
        "aud": RESOURCE,
        "exp": agora + 900,
        "iat": agora,
        "jti": "jti-int",
        "tenant_id": "11111111-1111-1111-1111-111111111111",
        "scopes": escopos,
        "grant_id": "grant-int",
        "client_id": "https://claude.ai/mcp-client",
    }
    claims.update(extra)
    return jwt.encode(claims, privada, algorithm="RS256")


def test_o_sdk_publica_o_documento_da_rfc_9728(servidor):
    """Descoberta pelo well-known — o SDK monta, nós não escrevemos.

    Se esta rota desaparecer numa atualização do SDK, o cliente MCP perde o
    caminho para saber ONDE autorizar, e o sintoma no Claude é um "não foi
    possível conectar" sem detalhe.
    """
    from starlette.testclient import TestClient

    app = servidor.streamable_http_app(stateless_http=True)
    with TestClient(app) as cliente:
        r = cliente.get("/.well-known/oauth-protected-resource")

    assert r.status_code == 200
    corpo = r.json()
    # Igualdade exata, de propósito: era `.rstrip("/")` e `ISSUER in a`, e por
    # isso o teste passava com o documento anunciando `".../"` enquanto o AS
    # anunciava `"..."`. O cliente compara string (RFC 8414 §3) — se afrouxamos
    # aqui, o teste passa e a conexão não conecta.
    assert corpo["resource"] == RESOURCE
    assert corpo["authorization_servers"] == [ISSUER]


def test_sem_token_responde_401_com_o_caminho_da_autorizacao(servidor):
    """O 401 tem de dizer onde autorizar, senão o cliente não tem como seguir.

    É também o contrato que o healthcheck do container usa: 401 é saúde.
    """
    from starlette.testclient import TestClient

    app = servidor.streamable_http_app(stateless_http=True)
    with TestClient(app) as cliente:
        r = cliente.post(
            "/mcp",
            json={"jsonrpc": "2.0", "id": 1, "method": "tools/list"},
            headers={"Accept": "application/json, text/event-stream"},
        )

    assert r.status_code == 401
    desafio = r.headers.get("www-authenticate", "")
    assert "Bearer" in desafio
    assert "resource_metadata" in desafio


def test_token_de_audiencia_alheia_e_recusado_pelo_caminho_http(servidor, chaves):
    """A mesma recusa do teste unitário, agora atravessando o middleware.

    Importa testar pelos dois caminhos: o unitário prova que o verificador
    recusa; este prova que o verificador está de fato ligado no app.
    """
    from starlette.testclient import TestClient

    privada, _ = chaves
    alheio = token(privada, ["atendimentos:read"], aud="https://outro.local")

    app = servidor.streamable_http_app(stateless_http=True)
    with TestClient(app) as cliente:
        r = cliente.post(
            "/mcp",
            json={"jsonrpc": "2.0", "id": 1, "method": "tools/list"},
            headers={
                "Accept": "application/json, text/event-stream",
                "Authorization": f"Bearer {alheio}",
            },
        )

    assert r.status_code == 401


def test_o_servidor_registra_as_28_tools_com_escopo_e_anotacao(servidor):
    """Invariantes do catálogo, verificadas no servidor montado de verdade."""
    registro = servidor._registro
    tools = registro.todos()

    assert len(tools) == 28
    # Nenhuma tool sem escopo: seria tool que qualquer token executa.
    assert all(t.escopos for t in tools)
    # Nomes válidos para a spec: [A-Za-z0-9_.-], até 128 caracteres.
    import re

    for t in tools:
        assert re.fullmatch(r"[A-Za-z0-9_.\-]{1,128}", t.nome), t.nome
    # Ordem de registro sem buracos — é ela que garante `tools/list` determinístico.
    assert [t.ordem for t in tools] == list(range(len(tools)))


def test_toda_tool_destrutiva_ou_de_envio_pede_confirmacao_no_schema(servidor):
    """O argumento `confirmar` tem de existir no schema, senão o agente não sabe.

    O guard recusa sem ele de qualquer forma — mas se o schema não o declarar, o
    modelo não tem como descobrir que precisa preenchê-lo, e fica preso num laço
    de tentativa e erro.
    """
    import asyncio

    from mcp.server.auth.middleware.auth_context import auth_context_var
    from mcp.server.auth.middleware.bearer_auth import AuthenticatedUser
    from mcp.server.auth.provider import AccessToken

    acesso = AccessToken(
        token="t",
        client_id="c",
        scopes=["tenant:admin"],
        resource=RESOURCE,
        subject="7",
        claims={"sub": "7", "scopes": ["tenant:admin"], "jti": "j"},
    )
    marca = auth_context_var.set(AuthenticatedUser(acesso))
    try:
        tools = asyncio.run(servidor.list_tools())
    finally:
        auth_context_var.reset(marca)

    registro = servidor._registro
    for t in tools:
        categoria = registro.exigir(t.name).categoria.value
        if categoria in ("envio", "destrutiva"):
            props = t.input_schema.get("properties", {})
            assert "confirmar" in props, f"{t.name} não declara `confirmar`"
            assert "dry_run" in props, f"{t.name} não declara `dry_run`"


def test_tools_de_escrita_declaram_dry_run(servidor):
    """`dry_run` é o que permite ao agente conferir antes de agir.

    Sem ele no schema, a única forma de o agente "testar" é executar.
    """
    import asyncio

    from mcp.server.auth.middleware.auth_context import auth_context_var
    from mcp.server.auth.middleware.bearer_auth import AuthenticatedUser
    from mcp.server.auth.provider import AccessToken

    acesso = AccessToken(
        token="t",
        client_id="c",
        scopes=["tenant:admin"],
        resource=RESOURCE,
        subject="7",
        claims={"sub": "7", "scopes": ["tenant:admin"], "jti": "j"},
    )
    marca = auth_context_var.set(AuthenticatedUser(acesso))
    try:
        tools = asyncio.run(servidor.list_tools())
    finally:
        auth_context_var.reset(marca)

    registro = servidor._registro
    for t in tools:
        if registro.exigir(t.name).categoria.value == "leitura":
            continue
        assert "dry_run" in t.input_schema.get("properties", {}), t.name
