"""ETL de migracao v1 (Django, DB-per-tenant) -> v2 (Rust, single-DB + RLS).

Ver README.md deste diretorio para o guia de uso. Este pacote NAO e importado
pelo runtime do v2 (server/); e uma ferramenta de operacao/cutover isolada,
rodada manualmente por um operador humano com acesso as credenciais reais.
"""

__version__ = "0.1.0"
