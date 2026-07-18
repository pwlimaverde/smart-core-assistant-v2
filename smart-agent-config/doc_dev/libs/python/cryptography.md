# cryptography (Fernet)

- **Versão Recomendada:** 43.x+ (qualquer 3.x+ serve para decifrar tokens Fernet legados)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-07-18
- **Propósito no Projeto:** ETL v1→v2 (fase N8.1, item 5) — **decifrar** as credenciais de tenant guardadas pela v1 Django (Fernet) para **recifrá-las** em AES-256-GCM via `CipherManager` da v2. Uso restrito ao script de migração em `infra/migracao-v1/`; a v2 NÃO adota Fernet.
- **Documentação Oficial:** https://cryptography.io/en/latest/fernet/
- **Library ID Context7:** `/pyca/cryptography`

---

## Histórico de Atualizações

- **2026-07-18** — Documentação inicial criada via Context7. Foco na recipe Fernet
  (decrypt/InvalidToken/MultiFernet), voltada à **leitura** das credenciais Fernet
  da v1 no ETL do N8. A v2 usa AES-256-GCM (`aes_gcm.md`), não Fernet.

---

## 1. Instalação

```bash
uv add cryptography   # apenas no ambiente do script de ETL
```

> Não precisa entrar no `pyproject` de runtime do `ia_engine` — é dependência
> exclusiva do utilitário de migração. Mantê-la fora do runtime evita superfície
> de ataque desnecessária.

---

## 2. Fernet — decifrar credenciais da v1

A v1 (Django) usa `cryptography.fernet.Fernet` com uma chave URL-safe base64 de
32 bytes (tipicamente em `settings.FERNET_KEY` / variável de ambiente do legado).

```python
from cryptography.fernet import Fernet, InvalidToken

def decifrar_credencial_v1(token: bytes | str, fernet_key: bytes | str) -> bytes:
    """Decifra um token Fernet da v1. Levanta InvalidToken se corrompido/chave errada."""
    f = Fernet(fernet_key)
    return f.decrypt(token)  # -> bytes (plaintext)
```

- `Fernet(key)` — `key`: `bytes` ou `str`, URL-safe base64, 32 bytes. **Thread-safe.**
- `decrypt(token, ttl=None)` — devolve o plaintext em `bytes`. Verifica assinatura
  (autenticado); **não passe `ttl`** ao migrar dados históricos (tokens são antigos
  e um `ttl` os rejeitaria como expirados).
- Lança `cryptography.fernet.InvalidToken` se o token for malformado, adulterado
  ou a chave não bater.

### Rotação de chave na v1 (MultiFernet)

Se a v1 rotacionou chaves, ela guarda uma **lista** de chaves. Use `MultiFernet`,
que tenta cada chave em ordem ao decifrar:

```python
from cryptography.fernet import Fernet, MultiFernet

def montar_multifernet(chaves_v1: list[bytes | str]) -> MultiFernet:
    return MultiFernet([Fernet(k) for k in chaves_v1])

# multi.decrypt(token) tenta chave 1, depois 2, ... -> InvalidToken se nenhuma servir.
```

---

## 3. Fluxo de recodificação no ETL (Fernet → AES-256-GCM)

```python
from cryptography.fernet import Fernet, InvalidToken
# CipherManager é o componente da v2 (Rust) exposto ao ETL, ou reimplementado
# no script conforme a estratégia de execução do N8.

def recodificar(token_fernet: bytes, fernet_key: bytes, cipher_v2) -> bytes:
    try:
        plano = Fernet(fernet_key).decrypt(token_fernet)   # bytes em claro (em memória)
    except InvalidToken:
        # registrar id da credencial (NUNCA o valor) e seguir para conciliação manual
        raise
    try:
        return cipher_v2.encrypt(plano)                    # AES-256-GCM da v2
    finally:
        # não há zeroing garantido de bytes em Python; minimize a janela e o escopo
        del plano
```

**Regras de segurança (invioláveis no projeto):**
- O plaintext da credencial **nunca** é escrito em disco nem em log — vive só em
  memória, o mínimo de tempo possível, entre decrypt e re-encrypt.
- Logs do ETL registram apenas **ids/contagens** e o resultado (ok/falha), jamais
  a chave Fernet, o token ou o valor decifrado.
- A `FERNET_KEY` da v1 entra por variável de ambiente/secret no momento do ETL e
  não é persistida no repositório.

---

## 4. Notas de Compatibilidade

- **Python >= 3.7** (validado no projeto com 3.13). Wheels binárias (não precisa
  compilar OpenSSL).
- Fernet = AES-128-CBC + HMAC-SHA256 (autenticado). É formato **da v1**; a v2
  padroniza AES-256-GCM — por isso o ETL só **lê** Fernet, nunca grava.
- `InvalidToken` é a única exceção de negócio relevante — trate-a por credencial
  (isola falha e alimenta o relatório de conciliação), sem abortar o lote inteiro.

---

## 5. Referências

| Recurso | Link |
|---------|------|
| Fernet (docs) | https://cryptography.io/en/latest/fernet/ |
| Pacote | https://pypi.org/project/cryptography/ |
| Repositório | https://github.com/pyca/cryptography |
| AES-256-GCM da v2 | `doc_dev/libs/rust/aes_gcm.md` |
