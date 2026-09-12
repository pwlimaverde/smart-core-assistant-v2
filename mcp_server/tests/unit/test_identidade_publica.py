"""A identidade pública precisa casar com a que o authorization server anuncia.

Regressão do defeito que impediu a PRIMEIRA conexão real (12/09/2026): o
consentimento gravava o grant, a tela "piscava", e a conexão não se completava.
Nada aparecia em log nosso, porque a recusa acontece dentro do cliente.

A causa era um caractere. O `control_plane` (Rust) normaliza e publica
`issuer: "https://auth…com.br"`; aqui a variável de ambiente vinha com barra
final e publicávamos `authorization_servers: ["https://auth…com.br/"]`. Pela
RFC 8414 §3 o cliente descobre o AS por essa URL e compara com o `issuer` que o
próprio AS anuncia — dois identificadores diferentes, e ele desiste.
"""

from mcp.shared.auth import ProtectedResourceMetadata

from mcp_server.settings import Settings


def _cfg(**kwargs) -> Settings:
    base = {
        "oauth_resource": "https://mcp.exemplo.com.br",
        "oauth_issuer": "https://auth.exemplo.com.br",
    }
    base.update(kwargs)
    return Settings(**base)


def test_barra_final_e_removida_do_resource_e_do_issuer() -> None:
    cfg = _cfg(
        oauth_resource="https://mcp.exemplo.com.br/",
        oauth_issuer="https://auth.exemplo.com.br/",
    )
    assert cfg.oauth_resource == "https://mcp.exemplo.com.br"
    assert cfg.oauth_issuer == "https://auth.exemplo.com.br"


def test_valor_ja_normalizado_nao_e_alterado() -> None:
    cfg = _cfg()
    assert cfg.oauth_resource == "https://mcp.exemplo.com.br"
    assert cfg.oauth_issuer == "https://auth.exemplo.com.br"


def test_url_do_documento_nao_ganha_barra_dupla() -> None:
    # `resource_metadata_url` já fazia `rstrip`; o teste garante que a
    # normalização nova não introduz uma segunda barra por engano.
    cfg = _cfg(oauth_resource="https://mcp.exemplo.com.br/")
    assert cfg.resource_metadata_url == (
        "https://mcp.exemplo.com.br/.well-known/oauth-protected-resource"
    )


def test_url_publicada_nao_ganha_a_barra_do_path_vazio() -> None:
    """O `rstrip` sozinho não bastava — e o defeito estava justamente aqui.

    `AnyHttpUrl("https://x")` devolve `https://x/`: o pydantic normaliza o path
    vazio. O `server.py` construía a URL assim, fora dos modelos do SDK, e a
    barra chegava pronta ao documento. Este teste olha para o **valor
    serializado**, que é o que o cliente lê, e não para a string de
    configuração, que já estava certa.
    """
    cfg = _cfg(
        oauth_resource="https://mcp.exemplo.com.br/",
        oauth_issuer="https://auth.exemplo.com.br/",
    )
    assert str(cfg.issuer_url) == "https://auth.exemplo.com.br"
    assert str(cfg.resource_url) == "https://mcp.exemplo.com.br"


def test_documento_do_recurso_casa_com_o_issuer_do_as() -> None:
    """A comparação que o cliente faz (RFC 8414 §3), reproduzida aqui.

    O `issuer` do AS é servido pelo `control_plane`, que faz
    `trim_end_matches('/')`. Se este lado publicar a variante com barra, os dois
    identificadores divergem e a conexão morre sem log nosso.
    """
    cfg = _cfg(oauth_issuer="https://auth.exemplo.com.br/")
    doc = ProtectedResourceMetadata(
        resource=cfg.resource_url,
        authorization_servers=[cfg.issuer_url],
    )
    publicado = doc.model_dump(mode="json")

    issuer_do_as = "https://auth.exemplo.com.br"  # como o Rust normaliza
    assert publicado["authorization_servers"] == [issuer_do_as]
    assert publicado["resource"] == "https://mcp.exemplo.com.br"
