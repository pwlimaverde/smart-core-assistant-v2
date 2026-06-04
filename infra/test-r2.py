#!/usr/bin/env python3
"""Teste de acesso ao storage S3-compatible (Cloudflare R2 / MinIO).

Valida ponta-a-ponta o que a crate `infrastructure_storage` fara em Rust:
conectar, enviar, listar, baixar (e conferir), gerar URL pre-assinada e remover.

As credenciais sao lidas de infra/.env.deploy (git-ignored) -NUNCA hardcode
segredos neste arquivo, que e versionado. Variaveis usadas:
  S3_ENDPOINT, S3_REGION, S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY,
  S3_BUCKET, S3_FORCE_PATH_STYLE

Execucao (sem instalar nada permanente, via uv):
  uv run --no-project --with boto3 python infra/test-r2.py

Opcional: aponte para outro arquivo de env com --env-file <caminho>.
"""

from __future__ import annotations

import argparse
import sys
import urllib.request
import uuid
from pathlib import Path


def carregar_env(caminho: Path) -> dict[str, str]:
    """Le um arquivo .env simples (KEY=VALUE) ignorando comentarios/linhas vazias."""
    if not caminho.exists():
        sys.exit(f"[ERRO] Arquivo de env nao encontrado: {caminho}")
    valores: dict[str, str] = {}
    for linha in caminho.read_text(encoding="utf-8").splitlines():
        linha = linha.strip()
        if not linha or linha.startswith("#") or "=" not in linha:
            continue
        chave, _, valor = linha.partition("=")
        valores[chave.strip()] = valor.strip().strip('"')
    return valores


def exigir(env: dict[str, str], chave: str) -> str:
    valor = env.get(chave, "")
    if not valor:
        sys.exit(f"[ERRO] Variavel obrigatoria ausente/vazia em .env.deploy: {chave}")
    return valor


def main() -> int:
    parser = argparse.ArgumentParser(description="Teste de acesso ao R2/S3.")
    parser.add_argument(
        "--env-file",
        default=str(Path(__file__).parent / ".env.deploy"),
        help="Caminho do arquivo de env (padrao: infra/.env.deploy).",
    )
    args = parser.parse_args()

    # Forca UTF-8 na saida para nao quebrar em consoles Windows (cp1252).
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

    try:
        import boto3
        from botocore.config import Config
        from botocore.exceptions import ClientError
    except ImportError:
        sys.exit(
            "[ERRO] boto3 nao instalado. Rode:\n"
            "  uv run --no-project --with boto3 python infra/test-r2.py"
        )

    env = carregar_env(Path(args.env_file))
    endpoint = exigir(env, "S3_ENDPOINT")
    region = env.get("S3_REGION", "auto")
    access_key = exigir(env, "S3_ACCESS_KEY_ID")
    secret_key = exigir(env, "S3_SECRET_ACCESS_KEY")
    bucket = exigir(env, "S3_BUCKET")
    path_style = env.get("S3_FORCE_PATH_STYLE", "true").lower() == "true"

    print("=" * 60)
    print("  TESTE DE ACESSO - STORAGE S3-COMPATIBLE (R2/MinIO)")
    print("=" * 60)
    print(f"  Endpoint : {endpoint}")
    print(f"  Regiao   : {region}")
    print(f"  Bucket   : {bucket}")
    print(f"  PathStyle: {path_style}")
    # Mostra so o prefixo da chave de acesso (nunca o secret).
    print(f"  AccessKey: {access_key[:6]}...")
    print("-" * 60)

    cfg = Config(
        region_name=region,
        signature_version="s3v4",
        s3={"addressing_style": "path" if path_style else "virtual"},
    )
    client = boto3.client(
        "s3",
        endpoint_url=endpoint,
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        config=cfg,
    )

    # Espelha o layout da crate: media/{tenant}/{instance}/{type}/{hash}
    chave = f"media/_selftest/{uuid.uuid4().hex}.txt"
    conteudo = b"smart-core-assistant-v2 :: teste de acesso R2\n"
    falhas = 0

    def ok(msg: str) -> None:
        print(f"  [OK]   {msg}")

    def erro(msg: str, exc: Exception) -> None:
        nonlocal falhas
        falhas += 1
        print(f"  [FALHA] {msg}: {exc}")

    # 1) Conectividade/credencial: HEAD no bucket.
    try:
        client.head_bucket(Bucket=bucket)
        ok("head_bucket -credenciais validas e bucket acessivel")
    except ClientError as exc:
        erro("head_bucket", exc)
        print("\n  Abortando: sem acesso ao bucket. Confira token/endpoint/bucket.")
        return 1

    # 2) Upload (PUT).
    try:
        client.put_object(
            Bucket=bucket, Key=chave, Body=conteudo, ContentType="text/plain"
        )
        ok(f"put_object -enviado '{chave}' ({len(conteudo)} bytes)")
    except ClientError as exc:
        erro("put_object", exc)

    # 3) Listagem por prefixo.
    try:
        resp = client.list_objects_v2(Bucket=bucket, Prefix="media/_selftest/")
        qtd = resp.get("KeyCount", 0)
        ok(f"list_objects_v2 -{qtd} objeto(s) sob o prefixo de teste")
    except ClientError as exc:
        erro("list_objects_v2", exc)

    # 4) Download (GET) + verificacao de conteudo.
    try:
        baixado = client.get_object(Bucket=bucket, Key=chave)["Body"].read()
        if baixado == conteudo:
            ok("get_object -conteudo conferido (bytes identicos)")
        else:
            erro("get_object", ValueError("conteudo divergente"))
    except ClientError as exc:
        erro("get_object", exc)

    # 5) URL pre-assinada (GET) + download HTTP direto.
    try:
        url = client.generate_presigned_url(
            "get_object", Params={"Bucket": bucket, "Key": chave}, ExpiresIn=120
        )
        with urllib.request.urlopen(url, timeout=30) as r:  # noqa: S310
            via_url = r.read()
        if via_url == conteudo:
            ok("presigned_url -download HTTP conferido (CDN/egress gratis)")
        else:
            erro("presigned_url", ValueError("conteudo divergente via URL"))
    except Exception as exc:  # urllib pode lancar varios tipos
        erro("presigned_url", exc)

    # 6) Remocao (DELETE) -limpa o objeto de teste.
    try:
        client.delete_object(Bucket=bucket, Key=chave)
        ok("delete_object -objeto de teste removido")
    except ClientError as exc:
        erro("delete_object", exc)

    print("-" * 60)
    if falhas == 0:
        print("  RESULTADO: TODOS OS TESTES PASSARAM [OK]")
        print("=" * 60)
        return 0
    print(f"  RESULTADO: {falhas} FALHA(S) [ERRO]")
    print("=" * 60)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
