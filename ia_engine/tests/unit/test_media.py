"""Testes do download de mídia (`shared/media.py`).

Mocka só a fronteira externa (`httpx.AsyncClient`) com um cliente fake —
nunca toca rede real. Cobre payload válido (bytes normais, dentro do
limite) e os caminhos de payload/resposta inválidos: URL vazia, erro HTTP,
corpo vazio e mídia acima do limite de tamanho.
"""

from __future__ import annotations

from typing import Any

import httpx
import pytest

from ia_engine.shared import media as media_module
from ia_engine.shared.media import MediaDownloadException, download_media


class _FakeResponse:
    """Resposta fake: expõe `.content` e `.raise_for_status()`."""

    def __init__(
        self, *, content: bytes = b"", raises: httpx.HTTPError | None = None
    ) -> None:
        self.content = content
        self._raises = raises

    def raise_for_status(self) -> None:
        if self._raises is not None:
            raise self._raises


class _FakeAsyncClient:
    """Cliente fake: registra chamadas de `get`/`aclose` para asserção."""

    def __init__(
        self,
        *,
        response: _FakeResponse | None = None,
        get_raises: httpx.HTTPError | None = None,
    ) -> None:
        self._response = response
        self._get_raises = get_raises
        self.closed = False
        self.requested_urls: list[str] = []

    async def get(self, url: str) -> _FakeResponse:
        self.requested_urls.append(url)
        if self._get_raises is not None:
            raise self._get_raises
        assert self._response is not None
        return self._response

    async def aclose(self) -> None:
        self.closed = True


# ------------------------------------------------------------------ inputs
@pytest.mark.asyncio
async def test_url_vazia_falha_sem_tocar_cliente():
    with pytest.raises(MediaDownloadException, match="não informada"):
        await download_media("")


# --------------------------------------------------------------- sucesso
@pytest.mark.asyncio
async def test_download_com_sucesso_devolve_bytes():
    fake_client = _FakeAsyncClient(
        response=_FakeResponse(content=b"\x00\x01conteudo-fake")
    )
    content = await download_media(
        "https://r2.example/audio.ogg", client=fake_client  # type: ignore[arg-type]
    )
    assert content == b"\x00\x01conteudo-fake"
    assert fake_client.requested_urls == ["https://r2.example/audio.ogg"]


@pytest.mark.asyncio
async def test_cliente_injetado_nao_e_fechado_pela_funcao():
    """Quando o `client` é injetado (não é dono), a função não deve
    fechá-lo — quem instanciou é responsável pelo ciclo de vida."""
    fake_client = _FakeAsyncClient(response=_FakeResponse(content=b"x"))
    await download_media("https://r2.example/x.jpg", client=fake_client)  # type: ignore[arg-type]
    assert fake_client.closed is False


@pytest.mark.asyncio
async def test_cliente_proprio_e_fechado_apos_o_download(
    monkeypatch: pytest.MonkeyPatch,
):
    """Sem `client` explícito, a função cria e fecha o próprio cliente."""
    created: list[_FakeAsyncClient] = []

    def _factory(*_args: Any, **_kwargs: Any) -> _FakeAsyncClient:
        client = _FakeAsyncClient(response=_FakeResponse(content=b"y"))
        created.append(client)
        return client

    monkeypatch.setattr(media_module.httpx, "AsyncClient", _factory)
    content = await download_media("https://r2.example/y.jpg")
    assert content == b"y"
    assert len(created) == 1
    assert created[0].closed is True


# ------------------------------------------------------------------ falhas
@pytest.mark.asyncio
async def test_erro_http_no_get_vira_media_download_exception():
    fake_client = _FakeAsyncClient(get_raises=httpx.ConnectError("sem rota"))
    with pytest.raises(MediaDownloadException, match="falha ao baixar"):
        await download_media("https://r2.example/audio.ogg", client=fake_client)  # type: ignore[arg-type]


@pytest.mark.asyncio
async def test_status_http_erro_vira_media_download_exception():
    resposta_404 = _FakeResponse(
        raises=httpx.HTTPStatusError(
            "404", request=httpx.Request("GET", "https://r2.example/x"), response=None  # type: ignore[arg-type]
        )
    )
    fake_client = _FakeAsyncClient(response=resposta_404)
    with pytest.raises(MediaDownloadException, match="falha ao baixar"):
        await download_media("https://r2.example/x.jpg", client=fake_client)  # type: ignore[arg-type]


@pytest.mark.asyncio
async def test_conteudo_vazio_vira_media_download_exception():
    fake_client = _FakeAsyncClient(response=_FakeResponse(content=b""))
    with pytest.raises(MediaDownloadException, match="conteúdo vazio"):
        await download_media("https://r2.example/x.jpg", client=fake_client)  # type: ignore[arg-type]


@pytest.mark.asyncio
async def test_midia_acima_do_limite_vira_media_download_exception():
    fake_client = _FakeAsyncClient(response=_FakeResponse(content=b"0123456789"))
    with pytest.raises(MediaDownloadException, match="excede o limite"):
        await download_media(
            "https://r2.example/grande.mp4",
            client=fake_client,  # type: ignore[arg-type]
            max_size=5,
        )
