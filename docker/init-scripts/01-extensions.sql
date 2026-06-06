-- Smart Core Assistant v2 — Extensoes PostgreSQL
-- Executado automaticamente pelo PostgreSQL na primeira inicializacao do container

-- Busca vetorial para RAG/embeddings (1536 dimensoes com pgvector)
CREATE EXTENSION IF NOT EXISTS vector;

-- Geracao de UUIDs nativos (usado em PKs de Tenant)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
