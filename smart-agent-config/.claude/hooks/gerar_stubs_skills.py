"""Gera `.claude/commands/<slug>.md` para as skills de uso manual.

A biblioteca única é `.context/skills/`. Os stubs só apontam para ela, com
`disable-model-invocation: true` (o modelo não vê a lista; o `/slug` continua
funcionando para o usuário). Nunca edite os stubs à mão: rode este script.

Uso: py -3 .claude/hooks/gerar_stubs_skills.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from roteador import ARQ_CONFIG, CLAUDE_DIR, DIR_SKILLS, _frontmatter  # noqa: E402

DIR_COMANDOS = CLAUDE_DIR / "commands"
MARCA_GERADO = "<!-- gerado por .claude/hooks/gerar_stubs_skills.py; não editar -->"


def _yaml_str(texto: str) -> str:
    return json.dumps(texto, ensure_ascii=False)


def stub(slug: str, descricao: str) -> str:
    return "\n".join(
        [
            "---",
            f"description: {_yaml_str(descricao if len(descricao) <= 250 else descricao[:247].rstrip() + '…')}",
            "disable-model-invocation: true",
            "argument-hint: [detalhes opcionais]",
            "---",
            MARCA_GERADO,
            f"<!-- stub-skill:{slug} -->",
            "",
            f"Leia e siga a skill `.context/skills/{slug}/SKILL.md` (biblioteca única de skills).",
            "Skills referenciadas por ela estão em `.context/skills/<outra>/SKILL.md` "
            "(ou via MCP dotcontext `skill getContent`).",
            "",
            "Detalhes do usuário: $ARGUMENTS",
            "",
        ]
    )


def main() -> int:
    config = json.loads(ARQ_CONFIG.read_text(encoding="utf-8"))
    DIR_COMANDOS.mkdir(parents=True, exist_ok=True)
    gerados = set()
    for slug in config["skills_manuais"]:
        meta = _frontmatter(DIR_SKILLS / slug / "SKILL.md")
        if not meta.get("description"):
            print(f"AVISO: skill {slug} sem SKILL.md/description na biblioteca", file=sys.stderr)
            continue
        (DIR_COMANDOS / f"{slug}.md").write_text(stub(slug, meta["description"]), encoding="utf-8")
        gerados.add(f"{slug}.md")
    # Remove stubs órfãos (gerados antes, mas que saíram da lista).
    for arq in DIR_COMANDOS.glob("*.md"):
        if arq.name not in gerados and MARCA_GERADO in arq.read_text(encoding="utf-8"):
            arq.unlink()
            print(f"removido stub órfão: {arq.name}")
    print(f"{len(gerados)} stubs gerados em {DIR_COMANDOS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
