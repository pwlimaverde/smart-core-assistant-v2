"""Gera os stubs Python do gRPC a partir do .proto canônico.

O `.proto` é a fonte de verdade compartilhada com o lado Rust e vive em
`server/crates/contracts/schemas/ai/ai_engine.proto`. Este script apenas o
compila para Python (não copia/reescreve o contrato). Saída (gitignored):
`src/ia_engine/contracts/`.

Uso:
    uv run python scripts/gen_proto.py
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

IA_ENGINE_ROOT = Path(__file__).resolve().parent.parent
REPO_ROOT = IA_ENGINE_ROOT.parent
PROTO_DIR = REPO_ROOT / "server" / "crates" / "contracts" / "schemas" / "ai"
PROTO_FILE = PROTO_DIR / "ai_engine.proto"
OUT_DIR = IA_ENGINE_ROOT / "src" / "ia_engine" / "contracts"


def main() -> int:
    if not PROTO_FILE.is_file():
        print(f"ERRO: .proto canônico não encontrado: {PROTO_FILE}")
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
        str(PROTO_FILE),
    ]
    print("Gerando stubs:", " ".join(cmd))
    result = subprocess.run(cmd, check=False)
    if result.returncode != 0:
        return result.returncode

    _fix_imports()
    print(f"Stubs gerados em {OUT_DIR}")
    return 0


def _fix_imports() -> None:
    """Corrige o import absoluto do `*_pb2_grpc.py` para import relativo.

    `grpc_tools.protoc` gera `import ai_engine_pb2 as ...` no arquivo
    `*_pb2_grpc.py`, que não resolve dentro do pacote `ia_engine.contracts`.
    Reescrevemos para import relativo do pacote.
    """
    grpc_file = OUT_DIR / "ai_engine_pb2_grpc.py"
    if not grpc_file.is_file():
        return
    text = grpc_file.read_text(encoding="utf-8")
    text = text.replace(
        "import ai_engine_pb2 as ai__engine__pb2",
        "from . import ai_engine_pb2 as ai__engine__pb2",
    )
    grpc_file.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
