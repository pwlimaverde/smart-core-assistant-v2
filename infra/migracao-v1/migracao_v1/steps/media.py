"""Step 7 (plano): migracao de midia legada (`MEDIA_ROOT` local da v1) -> R2.

Duas fontes de FileField na v1: `Contato.foto_perfil` e `Mensagem.arquivo_midia`
(`atendimentos/models.py`). Cobertura desta implementacao:

- `Mensagem.arquivo_midia` -> IMPLEMENTADO. Reusa a convencao de chave de
  `infrastructure_storage::keys::chave_midia` (crate Rust consumida pelo
  `data_storage`): `media/{tenant_id}/{instance_id}/{media_type}/{hash}[.ext]`
  (replicada aqui em `_montar_chave_midia`, ver docstring — mesmo layout, MESMOS
  nomes de segmento). `{instance_id}` real por mensagem NAO existe no modelo
  v1 (sem FK de `Mensagem` para uma instancia Evolution especifica — a
  associacao, quando existe, vive solta dentro de `metadados` json, de forma
  inconsistente entre linhas). Usamos um UUID fixo "instancia legado"
  (`INSTANCIA_LEGADO_UUID`, nil UUID) como placeholder — **decisao que
  precisa de revisao humana** (ver README).

- `Contato.foto_perfil` -> **NAO IMPLEMENTADO, TODO explicito**. Nao
  encontramos, na leitura rapida de `infrastructure_storage`, uma convencao
  de chave para avatares/fotos de perfil (so a de midia de mensagem,
  `chave_midia`, e a chave plana generica `StorageClient::chave` usada por
  outros uploads gerais). Migrar este campo exigiria inventar uma convencao
  nao documentada no codebase — em vez disso, documentamos o TODO e deixamos
  a coluna `foto_perfil` como veio da tabela v1 (path relativo antigo, que
  nao resolve mais para nada no v2 ate essa decisao ser tomada).
"""

from __future__ import annotations

import hashlib
import logging
import uuid
from pathlib import Path

from .. import db
from ..config import Config, S3Settings
from ..id_map import IdMap
from ..report import ReconciliationReport

INSTANCIA_LEGADO_UUID = uuid.UUID(int=0)
"""Placeholder usado como `{instance_id}` na chave R2 para midia migrada sem
uma instancia Evolution rastreavel por mensagem. TODO: revisar se ha uma
forma melhor de recuperar a instancia real a partir de `metadados` antes do
cutover (ver README, "Decisoes que precisam de revisao")."""

# Mapa `TipoMensagem` (v1) -> segmento de MediaType usado por `chave_midia`
# (Rust `infrastructure_storage::keys::MediaType::as_str()`).
_TIPO_PARA_MEDIA_TYPE = {
    "imageMessage": "image",
    "videoMessage": "video",
    "audioMessage": "audio",
    "documentMessage": "document",
    "stickerMessage": "sticker",
}


def _montar_chave_midia(
    tenant_id: str, instance_id: uuid.UUID, media_type: str, hash_hex: str, ext: str | None
) -> str:
    """Replica `infrastructure_storage::keys::chave_midia` (Rust) em Python.

    Layout: `media/{tenant_id}/{instance_id}/{media_type}/{hash}[.ext]`.
    """
    base = f"media/{tenant_id}/{instance_id}/{media_type}/{hash_hex}"
    return f"{base}.{ext}" if ext else base


async def migrar_midia_mensagens(
    cfg: Config,
    *,
    dry_run: bool,
    id_map: IdMap,
    report: ReconciliationReport,
    logger: logging.Logger,
    only_tenant_slug: str | None = None,
) -> None:
    """Upload de `Mensagem.arquivo_midia` para o R2 + rescrita da coluna no v2.

    Pre-requisito: `migrar_tenant_apps` ja deve ter rodado (precisa do id_map
    de `atendimentos.mensagem` para localizar a linha v2 correspondente).
    """
    if cfg.v1_media_root is None:
        raise ValueError("V1_MEDIA_ROOT nao configurada — necessaria para o step de midia")

    # Import tardio: aioboto3 e dependencia opcional (`pip install -e ".[storage]"`),
    # so exigida por quem realmente for rodar este step.
    try:
        import aioboto3
    except ImportError as exc:  # pragma: no cover - depende de ambiente
        raise RuntimeError(
            "aioboto3 nao instalado — rode `pip install -e \".[storage]\"` para usar o step de midia"
        ) from exc

    s3_settings = S3Settings.from_env()
    stat = report.nova_entidade("midia.mensagem_arquivo")

    v1_default_conn = await db.conectar_v1_default(cfg)
    v2_conn = await db.conectar_v2(cfg) if not dry_run else None
    session = aioboto3.Session()

    try:
        tenant_dbs, avisos = await db.descobrir_tenant_databases(v1_default_conn, cfg)
        for aviso in avisos:
            logger.warning(aviso)

        async with session.client(
            "s3",
            endpoint_url=s3_settings.endpoint,
            region_name=s3_settings.region,
            aws_access_key_id=s3_settings.access_key_id,
            aws_secret_access_key=s3_settings.secret_access_key.reveal(),
        ) as s3:
            for tenant_cfg in tenant_dbs:
                if only_tenant_slug and tenant_cfg.tenant_slug != only_tenant_slug:
                    continue

                tenant_conn = await db.abrir_conexao_tenant(tenant_cfg)
                try:
                    linhas = await tenant_conn.fetch(
                        "SELECT id, arquivo_midia, tipo FROM oraculo_mensagem "
                        "WHERE arquivo_midia IS NOT NULL AND arquivo_midia != ''"
                    )
                    for linha in linhas:
                        stat.v1_count += 1
                        id_v1 = linha["id"]
                        stat.registrar_id(id_v1)
                        caminho_relativo = linha["arquivo_midia"]
                        caminho_local = cfg.v1_media_root / caminho_relativo

                        if not caminho_local.is_file():
                            stat.conciliacao_manual.append(
                                f"tenant={tenant_cfg.tenant_slug} mensagem_id_v1={id_v1}: "
                                f"arquivo nao encontrado em {caminho_local} (V1_MEDIA_ROOT)"
                            )
                            continue

                        dados = caminho_local.read_bytes()
                        hash_hex = hashlib.sha256(dados).hexdigest()
                        media_type = _TIPO_PARA_MEDIA_TYPE.get(linha["tipo"], "document")
                        ext = Path(caminho_relativo).suffix.lstrip(".") or None
                        chave = _montar_chave_midia(
                            tenant_cfg.tenant_id, INSTANCIA_LEGADO_UUID, media_type, hash_hex, ext
                        )

                        if dry_run:
                            continue

                        await s3.put_object(Bucket=s3_settings.bucket, Key=chave, Body=dados)

                        id_v2 = id_map.get(tenant_cfg.tenant_slug, "atendimentos.mensagem", id_v1)
                        if id_v2 is None:
                            stat.conciliacao_manual.append(
                                f"tenant={tenant_cfg.tenant_slug} mensagem_id_v1={id_v1}: "
                                "upload feito mas id_v2 nao encontrado no id_map "
                                "(rode migrar_tenant_apps antes deste step)"
                            )
                            continue

                        assert v2_conn is not None
                        await v2_conn.execute(
                            "UPDATE oraculo_mensagem SET arquivo_midia = $1 WHERE id = $2",
                            chave,
                            id_v2,
                        )
                        stat.v2_written_update += 1
                finally:
                    await tenant_conn.close()
    finally:
        await v1_default_conn.close()
        if v2_conn is not None:
            await v2_conn.close()
