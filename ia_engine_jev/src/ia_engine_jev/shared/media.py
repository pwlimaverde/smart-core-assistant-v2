"""Download de mídia a partir de URL pré-assinada (R2).

Nunca aceitamos binário inline — a mídia sempre chega por `MediaRef.url`.

Camada técnica ("burra"): falha lançando `MediaDownloadException`, que os
repositórios das features de mídia traduzem para o caso de domínio
`MediaDownloadError` via `map_error`.
"""

from __future__ import annotations

import httpx

_DOWNLOAD_TIMEOUT_SECONDS = 30.0
_MAX_MEDIA_SIZE_BYTES = 25 * 1024 * 1024  # 25MB


class MediaDownloadException(Exception):
    """Falha técnica no download da mídia (URL vazia, HTTP != 2xx, tamanho)."""


async def download_media(
    url: str,
    *,
    timeout: float = _DOWNLOAD_TIMEOUT_SECONDS,
    max_size: int = _MAX_MEDIA_SIZE_BYTES,
    client: httpx.AsyncClient | None = None,
) -> bytes:
    """Baixa a mídia da URL pré-assinada.

    Raises:
        MediaDownloadException: URL vazia, resposta vazia, HTTP != 2xx, ou
            mídia acima do limite de tamanho.
    """
    if not url:
        raise MediaDownloadException("URL da mídia não informada")

    owns_client = client is None
    http = client or httpx.AsyncClient(timeout=timeout, follow_redirects=True)
    try:
        response = await http.get(url)
        response.raise_for_status()
        content = response.content
    except httpx.HTTPError as exc:
        raise MediaDownloadException(f"falha ao baixar mídia: {exc}") from exc
    finally:
        if owns_client:
            await http.aclose()

    if not content:
        raise MediaDownloadException("download de mídia retornou conteúdo vazio")
    if len(content) > max_size:
        raise MediaDownloadException(
            f"mídia excede o limite de {max_size // (1024 * 1024)}MB"
        )
    return content
