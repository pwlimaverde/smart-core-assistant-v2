# Módulo Configurações Globais

Este documento detalha os modelos responsáveis pelas configurações dinâmicas e variáveis de ambiente globais do sistema (Core), residindo na base de dados unificada de forma isolada das configurações específicas de tenants. Ele funciona sob um padrão genérico de chave-valor dinâmico, permitindo que novos parâmetros ou integrações sejam adicionados sem requerer migrações no banco de dados.

---

## 1. Módulo: `settings_manager`

### `CoreSettings`
Armazena de forma persistente e dinâmica todas as chaves de API globais (como tokens mestres da OpenAI, Groq, Gemini) e flags operacionais da plataforma. Substitui o antigo Firebase Remote Config do legado.

*   **Nome da Tabela:** `settings_manager_coresettings`
*   **Campos:**
    *   `id` (INT, Chave Primária): ID incremental automático.
    *   `key` (VARCHAR(255), Não Nulo, Único): Chave identificadora da configuração (ex: `GROQ_API_KEY`, `EVOLUTION_SERVER_URL`, `EVOLUTION_GLOBAL_TOKEN`).
    *   `value` (TEXT, Não Nulo): Valor da configuração associado à chave.
    *   `encrypted` (BOOLEAN, Padrão: `False`): Se ativado, sinaliza que o valor está criptografado em repouso. O backend o descriptografa em tempo de cache-miss/leitura utilizando a chave simétrica do servidor (`ENCRYPTION_KEY`).
    *   `description` (TEXT, Opcional/Vazio): Descrição detalhada do parâmetro para documentação no painel administrativo.
    *   `created_at` (TIMESTAMPTZ, Não Nulo): Data/hora de criação do registro.
    *   `updated_at` (TIMESTAMPTZ, Não Nulo): Data/hora da última alteração de valor.

*   **Métodos de Código:**
    *   `get_value() -> str`: Caso o campo `encrypted` seja verdadeiro, descriptografa o `value` utilizando criptografia simétrica AES-GCM-256 com a chave do servidor. Se falso, retorna a string de texto simples.

*   **Configurações de Ordenação:** Ordenado por `key` alfabeticamente.

---

## 2. Flexibilidade e Invalidação de Cache

1.  **Sem Migrações de Banco:** Toda vez que surgir uma nova plataforma de IA (ex: Anthropic) ou um novo threshold global, o administrador simplesmente adiciona uma nova linha na tabela `CoreSettings` pelo painel de Backoffice. Nenhuma alteração de esquema físico é necessária.
2.  **Mecanismo de Cache:** O backend (Rust) faz o carregamento inicial de todas as linhas de `CoreSettings` em um mapa dinâmico em memória. Em caso de alteração no painel, o sistema publica um sinal de invalidação no Redis (`core:settings:invalidate`), forçando o recarregamento instantâneo do cache em runtime em todos os contêineres de execução (Rust e Python) sem necessidade de downtime.
