# Central de Bibliotecas (doc_dev/libs)

Este diretório contém a documentação atualizada de todas as bibliotecas utilizadas no desenvolvimento do **Smart Core Assistant v2**, segregadas por linguagem de programação. 

O objetivo deste espaço é duplo:
1. **Auxiliar os agentes autônomos** a compreenderem o propósito de cada biblioteca, seus padrões de implementação preferenciais e as restrições arquiteturais associadas.
2. **Facilitar a governança de versões**, permitindo identificar rapidamente quais dependências estão atualizadas, em homologação ou desatualizadas.

---

## 1. Estrutura de Pastas

```
doc_dev/libs/
├── README.md               # Este arquivo de instruções
├── rust/                   # Bibliotecas utilizadas no Backend (Rust)
├── python/                 # Bibliotecas utilizadas no AI Engine (Python)
└── flutter/                # Bibliotecas utilizadas no Frontend (Dart/Flutter)
```

---

## 2. Cabeçalho Padrão de Metadados

Toda biblioteca documentada deve começar obrigatoriamente com o seguinte bloco de metadados no topo do arquivo Markdown. Isso permite que agentes de automação façam parsing do estado da biblioteca:

```markdown
# [Nome da Biblioteca]

- **Versão Recomendada:** [Versão mais recente utilizada, ex: 1.0.0]
- **Status de Atualização:** [✅ ATUALIZADA / ⚠️ DESATUALIZADA / 🔍 EM_HOMOLOGACAO]
- **Última Verificação:** [Data da última conferência no formato AAAA-MM-DD]
- **Propósito no Projeto:** [Uma frase curta descrevendo a função da lib no sistema]
- **Documentação Oficial:** [URL da documentação oficial da biblioteca]
```

### Explicação dos Status:
*   `✅ ATUALIZADA`: A versão recomendada está em produção/uso estável no projeto e é a mais recente da comunidade.
*   `⚠️ DESATUALIZADA`: Existe uma versão mais recente na comunidade com correções ou novos recursos necessários.
*   `🔍 EM_HOMOLOGACAO`: Uma versão mais recente está em testes/desenvolvimento local, mas ainda não foi homologada.

---

## 3. Instruções para Inclusão de Nova Biblioteca

Quando um desenvolvedor ou agente precisar introduzir uma nova biblioteca no projeto:

1.  **Adicionar a Dependência no Gerenciador de Pacotes:**
    *   **Rust:** Adicionar no `Cargo.toml` correspondente (ou no nível do workspace `[workspace.dependencies]`).
    *   **Python:** Adicionar no `pyproject.toml` usando o comando do `uv` (`uv add <lib>`).
    *   **Flutter:** Adicionar no `pubspec.yaml` do app ou pacote correspondente (`flutter pub add <lib>`).
2.  **Criar o Arquivo de Documentação:**
    *   Crie um arquivo `<nome-da-lib>.md` no subdiretório da respectiva linguagem.
    *   Preencha o **Cabeçalho Padrão** (Seção 2).
    *   Descreva brevemente o **Guia de Uso Rápido** focado no contexto do projeto (incluindo exemplos de código com Clean Code e padrões de tratamento de erro do projeto).
3.  **Atualizar o README da Linguagem:**
    *   Adicione o link para a nova biblioteca na tabela ou lista do README correspondente da linguagem (se houver).

---

## 4. Instruções para Atualização de Biblioteca Existente

Para atualizar a versão de uma biblioteca:

1.  **Executar a Atualização Técnica:**
    *   Faça o update no gerenciador de pacotes da respectiva stack.
    *   Valide se o código compila perfeitamente e se não há quebras de compatibilidade.
    *   *Nota:* Lembre-se que você **não deve gerar arquivos de testes**, mas deve garantir que o build e os linters (`cargo clippy`, `ruff`, `dart analyze`) passem com sucesso.
2.  **Alterar o Status na Documentação:**
    *   Abra o arquivo `<nome-da-lib>.md`.
    *   Atualize o campo `Versão Recomendada` para a nova versão desejada, altere o `Status de Atualização` para `🔍 EM_HOMOLOGACAO` durante os testes ou `✅ ATUALIZADA` assim que estiver estável na branch `dev`.
    *   Atualize o campo `Última Verificação` com a data atual.
3.  **Registrar Notas de Atualização:**
    *   No corpo do documento da biblioteca, crie ou atualize a seção `## Histórico de Atualizações` detalhando os motivos do bump (ex: correção de bug, performance, melhor compatibilidade).
