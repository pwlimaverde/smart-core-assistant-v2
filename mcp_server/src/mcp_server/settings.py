"""Configuração do servidor MCP, toda por ambiente.

Nenhum segredo é logado no startup — nem o endpoint interno, nem o segredo de
serviço, nem a chave pública (que não é segredo, mas polui o log e esconde o que
importa). O que sai no log é o que ajuda a diagnosticar: porta, URLs públicas e
se o verificador de token está configurado.
"""

from __future__ import annotations

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="MCP_", extra="ignore")

    # --- Identidade pública -------------------------------------------------

    #: URL deste resource server. É o `aud` que todo access token precisa ter.
    #: Token com audiência diferente é recusado — é a defesa contra um token
    #: emitido para outro serviço ser reaproveitado aqui.
    oauth_resource: str = Field(default="https://mcp.smartcoreassistant.com.br")

    #: URL do authorization server (o `control_plane`). Vai no documento de
    #: metadados do recurso (RFC 9728) e é o `iss` esperado nos tokens.
    oauth_issuer: str = Field(default="https://auth.smartcoreassistant.com.br")

    # --- Validação de token -------------------------------------------------

    #: Chave **pública** RSA (PEM) do authorization server.
    #:
    #: Pública de propósito: com ela este processo *confere* tokens e não
    #: consegue *emitir* nenhum. Um servidor exposto à internet, que executa
    #: entrada de terceiros, não pode ter poder de emissão.
    oauth_public_key_pem: str = Field(default="")

    #: Segredo de serviço para a troca interna de token no `control_plane`.
    #: Identifica o processo, não um usuário.
    service_secret: str = Field(default="")

    #: Endpoint da troca interna. Rede interna, sem TLS: é `mcp_net`.
    token_exchange_url: str = Field(
        default="http://control_plane:8095/internal/mcp/token-exchange"
    )

    # --- Backend ------------------------------------------------------------

    #: gRPC do `runtime_api`. É a ÚNICA porta de dados deste processo: não há
    #: `DATABASE_URL` aqui, e o container nem alcança o Postgres pela rede.
    runtime_endpoint: str = Field(default="runtime_api:50051")

    #: Deadline das chamadas ao backend. 30s porque `encaminhar_tenant` fala com
    #: a Evolution (WhatsApp) em algumas rotas e o cliente não pode ser mais
    #: curto que o servidor — senão a chamada é abortada aqui depois de o efeito
    #: já ter acontecido lá.
    runtime_timeout_s: float = Field(default=30.0)

    # --- Transporte ---------------------------------------------------------

    host: str = Field(default="0.0.0.0")
    port: int = Field(default=8099)

    #: Caminho do endpoint MCP. É o que o usuário cola no conector.
    http_path: str = Field(default="/mcp")

    # --- Limites (§5.4 do plano; rate limit é MUST da spec) -----------------

    rate_leitura_min: int = Field(default=300)
    rate_config_min: int = Field(default=60)
    rate_envio_min: int = Field(default=10)
    rate_envio_dia: int = Field(default=100)
    rate_destrutiva_min: int = Field(default=5)
    rate_destrutiva_dia: int = Field(default=30)

    #: Teto de itens devolvidos por uma tool de listagem. Independe do que o
    #: agente pedir: uma lista de 5 mil contatos não ajuda o modelo e enche a
    #: janela de contexto dele com dado que ele não vai usar.
    max_itens_por_pagina: int = Field(default=50)

    @property
    def chave_publica(self) -> str:
        """A chave pública com quebras de linha reais.

        O `env_file` do Docker Compose **não** aceita valor multilinha, então o
        PEM é gravado numa linha só, com `\\n` escapado. O que chega aqui depende
        do dialeto dotenv da versão do Compose: algumas interpretam o escape,
        outras entregam os dois caracteres literais. Um PEM com `\\n` literal é
        recusado pelo `cryptography`, e o sintoma seria **todo token rejeitado**
        com "chave inválida" — um servidor de pé que não atende ninguém.

        Medido em 2026-09-11 (Docker Compose 5.1.4): o `env_file:` do Compose
        remove as aspas e converte `\\n` em quebra real — ou seja, o caminho do
        deploy já entrega o PEM pronto. Já o `docker run --env-file` **mantém as
        aspas** no valor e não converte nada, e é ele que alguém usa ao depurar um
        container à mão. As três formas são aceitas; quando o valor já está certo,
        a normalização é no-op.
        """
        bruto = self.oauth_public_key_pem
        podado = bruto.strip()
        if len(podado) >= 2 and podado[0] == podado[-1] and podado[0] in "\"'":
            bruto = podado[1:-1]
        return bruto.replace("\\n", "\n") if "\\n" in bruto else bruto

    @property
    def resource_metadata_url(self) -> str:
        """URL do documento RFC 9728, citada no header `WWW-Authenticate`."""
        base = self.oauth_resource.rstrip("/")
        return f"{base}/.well-known/oauth-protected-resource"

    def resumo_seguro(self) -> dict[str, object]:
        """O que pode ir para o log de startup.

        Segredos entram como booleano ("está configurado?"), nunca como valor.
        """
        return {
            "resource": self.oauth_resource,
            "issuer": self.oauth_issuer,
            "runtime_endpoint": self.runtime_endpoint,
            "porta": self.port,
            "caminho": self.http_path,
            "chave_publica_configurada": bool(self.oauth_public_key_pem),
            "segredo_de_servico_configurado": bool(self.service_secret),
        }


def carregar() -> Settings:
    return Settings()
