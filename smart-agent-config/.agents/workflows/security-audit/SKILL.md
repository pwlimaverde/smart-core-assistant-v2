---
name: security-audit
description: Review code and infrastructure for security weaknesses. Use when Reviewing code for security vulnerabilities, Assessing authentication/authorization, or Checking for OWASP top 10 issues
---

## Workflow

1. Review authentication implementation
2. Check authorization on all endpoints
3. Look for injection vulnerabilities
4. Verify input validation and sanitization
5. Check for sensitive data exposure
6. Review dependency security
7. Document findings with severity

## Project-Specific Checks

- Policies RLS em todas as tabelas de domínio (verificar `CREATE POLICY`)
- `tenant_id` obrigatório em todas as queries (filtro duplo: app + RLS)
- `SET app.current_tenant = ''` sem UUID válido deve rejeitar operações
- `messaging_gateway`: validação de assinatura do Evolution Go
- `local_engine` (FFI) não pode expor dados de outros tenants
- Logs sem PII ou conteúdo de mensagens de clientes

## Quality Bar

- Check OWASP top 10 vulnerabilities
- Never trust user input
- Verify authorization on all routes
- Document findings with clear severity levels
