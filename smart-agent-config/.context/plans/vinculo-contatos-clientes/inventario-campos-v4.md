# V4 — Inventário dos campos do cadastro

Fonte: migrations `0004`, `0045`, `0050`, `0052`, `0053` e o modelo de domínio
do `operacional_module` (`contato_da_conversa.dart`). Este documento é o que o
código tem hoje. O conjunto mínimo por tipo (contato, cliente PF, cliente PJ)
depende da **D3** e ainda não foi definido.

## oraculo_contato (contato do WhatsApp)

| Coluna | No app | Observação |
| --- | --- | --- |
| `telefone` | Exibido; só leitura na edição | Chave do contato (único por tenant) |
| `nome_contato` | Editável (Editar contato) | Preenchido pela IA se vazio (P15) |
| `email` | Editável | Pela IA quando válido; marca "pela conversa" |
| `nome_perfil_whatsapp` | Exibido | Vem do WhatsApp; não editável |
| `cargo` (0052) | Editável | |
| `segmento` (0052) | Editável | |
| `observacoes` (0052) | Editável | |
| `foto_perfil`, `foto_perfil_url_origem` | Exibido como miniatura | Pedido de foto removido; iniciais no lugar |
| `metadados.entidades` | Só leitura (seção "Dados do contato") | Entidades que a IA guardou; sem coluna própria |
| `ativo`, `slug`, `data_cadastro`, `ultima_interacao` | Não exibidos | Controle interno |
| `campos_pela_ia` (0053) | Lido para marcar "pela conversa" | Array de colunas preenchidas pela IA |

## oraculo_cliente (cliente PF ou PJ)

| Coluna | No app | Observação |
| --- | --- | --- |
| `nome_fantasia` | Editável | Nome exibido na lista e na ficha |
| `razao_social` | Editável | Usado em PJ |
| `tipo` | Editável | `pf` ou `pj` |
| `cpf` | Editável; validado (dígito verificador) | Único por tenant quando preenchido |
| `cnpj` | Editável; validado (dígito verificador) | Único por tenant quando preenchido |
| `telefone`, `site` | Editáveis | |
| `ramo_atividade` | Editável como segmento | |
| `cargo_responsavel` (0052) | Editável | |
| `observacoes` | Editável | |
| `cep`, `logradouro`, `numero`, `complemento`, `bairro`, `cidade`, `uf` | Editáveis; preenchíveis pela conversa | Só em campo vazio, com frase de origem (ver endereço pela conversa) |
| `pais` | Não exposto | Default "Brasil" |
| `campos_pela_ia` (0053) | Lido para marcar "pela conversa" | |
| `metadados` | Não exposto | |
| `ativo`, `slug`, `data_cadastro`, `ultima_atualizacao` | Não exibidos | Controle interno |

## O que falta decidir (D3)

- Quais campos são obrigatórios em contato, cliente PF e cliente PJ.
- Se `pais` e `metadados` devem ser expostos ao operador.
- Se `ramo_atividade` e o campo de segmento do contato são o mesmo conceito.

Até a D3, a validação no servidor cobre só o que já é regra hoje: documento
com dígito verificador, UF com duas letras e CEP com oito dígitos.
