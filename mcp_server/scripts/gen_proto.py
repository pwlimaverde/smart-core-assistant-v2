"""Gera os stubs Python do gRPC a partir dos `.proto` canônicos.

O contrato é compartilhado com o lado Rust e vive em
`server/crates/contracts/schemas/queries/`. Este script apenas o compila para
Python — não copia nem reescreve o contrato. Saída (gitignored):
`src/mcp_server/grpc/contracts/`.

`--pyi_out` entra junto porque o mypy roda em modo estrito o suficiente para que
stubs sem tipos derrubem o CI.

Uso:
    uv run python scripts/gen_proto.py
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

MODULO_ROOT = Path(__file__).resolve().parent.parent
REPO_ROOT = MODULO_ROOT.parent
PROTO_DIR = REPO_ROOT / "server" / "crates" / "contracts" / "schemas" / "queries"
# `admin.proto` carrega o `AdminService` inteiro (89 RPCs); `auth.proto` entra
# pelas mensagens de sessão que algumas respostas referenciam.
PROTOS = ("admin.proto", "auth.proto")
OUT_DIR = MODULO_ROOT / "src" / "mcp_server" / "grpc" / "contracts"


def main() -> int:
    faltando = [p for p in PROTOS if not (PROTO_DIR / p).is_file()]
    if faltando:
        print(f"ERRO: .proto canônico não encontrado: {faltando} em {PROTO_DIR}")
        return 1

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUT_DIR / "__init__.py").write_text(
        '"""Stubs gRPC gerados (gitignored). Ver scripts/gen_proto.py."""\n',
        encoding="utf-8",
    )

    cmd = [
        sys.executable,
        "-m",
        "grpc_tools.protoc",
        f"--proto_path={PROTO_DIR}",
        f"--python_out={OUT_DIR}",
        f"--grpc_python_out={OUT_DIR}",
        f"--pyi_out={OUT_DIR}",
        *[str(PROTO_DIR / p) for p in PROTOS],
    ]
    print("Gerando stubs:", " ".join(cmd))
    resultado = subprocess.run(cmd, check=False)
    if resultado.returncode != 0:
        return resultado.returncode

    _corrigir_imports()
    print(f"Stubs gerados em {OUT_DIR}")
    return 0


def _corrigir_imports() -> None:
    """Torna relativos os imports absolutos que o protoc gera.

    O `grpc_tools.protoc` emite `import admin_pb2 as admin__pb2` nos arquivos
    `*_pb2_grpc.py`, o que não resolve dentro do pacote
    `mcp_server.grpc.contracts`.
    """
    for proto in PROTOS:
        base = proto.removesuffix(".proto")
        arquivo = OUT_DIR / f"{base}_pb2_grpc.py"
        if not arquivo.is_file():
            continue
        texto = arquivo.read_text(encoding="utf-8")
        texto = texto.replace(
            f"import {base}_pb2 as {base}__pb2",
            f"from . import {base}_pb2 as {base}__pb2",
        )
        arquivo.write_text(texto, encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
