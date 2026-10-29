# Documentação Auxiliar — Vínculo contato ↔ cliente, lista branca e campos do cadastro

> Gerado em: 17/10/2026
> Plano canônico: `.context/plans/vinculo-contatos-clientes.md`
> Plano completo: `.context/plans/vinculo-contatos-clientes/plano_completo_vinculo-contatos-clientes.md`

## Estado da verificação

- **Central local `doc_dev/libs/`:** não existe no repositório. Todas as libs ficam em **CRIAR** pela regra da skill.
- **Context7:** o conector `claude.ai Context7` pede autenticação e não está ativo nesta sessão. Não houve consulta à documentação atual das libs.
- **MCP dotcontext:** fora do ar (timeout de conexão). Sem `scaffoldPlan`, `workflow-init` nem `plan link`.
- **Consequência:** as versões abaixo vêm dos manifests do projeto. Nenhuma API foi confirmada contra a documentação oficial atual. Antes da fase V3 (extração pela conversa), a verificação precisa ser feita (ver "Pendências de verificação").

## Grupo A — Libs que o plano toca

Este plano não exige lib nova. Validação de CPF/CNPJ (dígito verificador) e de e-mail é implementada no próprio código, sem dependência externa.

### Python — `ia_engine_jev/pyproject.toml`
| Lib | Versão no manifest | Uso no plano |
|---|---|---|
| `pydantic` | `>=2.12` | Modelo do campo extraído (valor, confiança, frase de origem) em V3 |
| `pydantic-settings` | `>=2.6` | Já usado pelo serviço; sem mudança |
| `typesafe-sdk[http2]` | `==0.7.2` (versão fixa) | Jev (TypeSafe). V3 **não** muda o motor de decisão; a extração de valor livre segue o padrão "a LLM extrai, o código valida" do plano `ia-engine-jev` |
| `grpcio`, `protobuf` | `>=1.68`, `>=5.28` | Contrato gRPC com o worker (campos novos em V3) |

### Rust — `server/Cargo.toml`
| Lib | Versão | Uso no plano |
|---|---|---|
| `sqlx` | `0.9` | Consultas de vínculo, auditoria e campos. Mudança em `query!` exige regenerar `.sqlx` com `[sqlx-prepare]` |
| `serde` | `1.0` (derive) | Payloads de auditoria e do contrato |

### Flutter — `clients/apps/smart-core-tenant/pubspec.yaml` e design system
Sem libs novas. Usa `design_system_module` (tokens e `AppTheme`) e os módulos `operacional_module` e `tenant_module`.

## Grupo B — Serviços externos

Nenhum serviço externo é chamado por este plano. A extração de campos pela conversa usa o motor de IA já existente (`ia_engine` / `ia_engine_jev`). Não há novo endpoint de terceiros.

## Grupo C — Observabilidade e auditoria (levantamento)

Dados sensíveis envolvidos: **CPF, CNPJ, e-mail, telefone e endereço** de clientes. Pela `doc_dev/modelagem_dados/08_diretrizes_seguranca.md` §4.2, acesso e alteração de dado protegido entram na trilha de auditoria.

| Ponto | Dado sensível | Regra |
|---|---|---|
| Log de vínculo/edição | telefone, CPF/CNPJ | Nunca logar o valor. Telefone mascarado (padrão já usado em `whitelist.adicionada`). Logar só IDs (`contato_id`, `cliente_id`) |
| Log da extração pela IA | valor do campo | Logar contagem e nome do campo, nunca o valor nem a frase do cliente |
| `audit_log` | valor alterado | Registrar nome do campo alterado e o `message_id` de origem. Valor só dentro do registro de dado (não em log) |
| Payloads gRPC | CPF/CNPJ | Campos novos não entram em mensagens de erro. `error_code` apenas |

Eventos de auditoria propostos (ver plano completo, seção por fase): `contato.editado`, `contato.vinculado_cliente`, `contato.desvinculado_cliente`, `contato.vinculo_sugerido_ia`, `cliente.dado_alterado_ia`, `campo.criado`, `campo.atualizado`, `campo.desativado`.

## Pendências de verificação (antes de codificar)

1. Conferir a API atual de `pydantic` 2.12 para validação com `Field(description=...)` e `model_validate_json` (V3).
2. Confirmar com `sqlx 0.9` o formato de `query!` e a regeneração de `.sqlx` (V1 e V4).
3. Se o Context7 for reativado: criar `doc_dev/libs/python/pydantic.md` e `doc_dev/libs/rust/sqlx.md` com o cabeçalho padrão, para as próximas reestruturações.
