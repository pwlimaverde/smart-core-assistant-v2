# Módulo Configurações Globais

Este documento detalha os modelos responsáveis pelas configurações dinâmicas e variáveis de ambiente globais do sistema (Core), residindo na base de dados unificada de forma isolada das configurações específicas de tenants.

---

## 1. Módulo: `settings_manager`

### `CoreSettings`
Armazena de forma persistente as chaves de API globais (como tokens mestres da OpenAI, Groq, Gemini) e flags de comportamento gerais da plataforma. Substitui o antigo Firebase Remote Config do legado.

*   **Nome da Tabela:** `settings_manager_coresettings`
*   **Campos:**
    *   `id` (INT, Chave Primária): ID incremental automático.
    *   `key` (VARCHAR(255), Não Nulo, Único): Chave identificadora da configuração (ex: `OPENAI_API_KEY`, `EVOLUTION_SERVER_URL`, `EVOLUTION_GLOBAL_TOKEN`).
    *   `value` (TEXT, Não Nulo): Valor da configuração associado à chave.
    *   `encrypted` (BOOLEAN, Padrão: `False`): Se ativado, descriptografa o conteúdo em tempo de leitura chamando `get_value()`.
    *   `description` (TEXT, Opcional/Vazio): Descrição detalhada do parâmetro para fins de documentação no painel administrativo.
    *   `created_at` (TIMESTAMPTZ, Não Nulo): Data/hora de criação do registro.
    *   `updated_at` (TIMESTAMPTZ, Não Nulo): Data/hora da última alteração de valor.
*   **Métodos de Código:**
    *   `get_value() -> str`: Caso o campo `encrypted` seja verdadeiro, descriptografa o `value` utilizando criptografia simétrica AES-GCM com a chave do servidor (`ENCRYPTION_KEY`). Se falso, retorna a string de texto simples.
*   **Configurações de Ordenação:** Ordenado por `key` alfabeticamente.
