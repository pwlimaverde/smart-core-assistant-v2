---
type: skill
name: Test Generation
description: Generate comprehensive test cases for code. Use when Writing tests for new functionality, Adding tests for bug fixes (regression tests), or Improving test coverage for existing code
skillSlug: test-generation
phases: [E, V]
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---
## Workflow

1. Identifique a stack e o padrão: **Rust → siga a skill `test-rust`** (canônica); Python → pytest + pytest-asyncio via `uv`; Flutter → `flutter_test` (unit + widget)
2. Liste os comportamentos a testar: caminho feliz, bordas, variantes de erro
3. Cubra as invariantes do projeto quando tocadas: política de ticket, idempotência (`wa_message_id`), RLS/cross-tenant negado, debounce, bot bloqueado
4. Banco real para integração (transação+rollback) — nunca mock de banco; mock só nas fronteiras externas (LLM, Evolution Go) sobre traits
5. Nomes comportamentais em inglês; comentários em pt-br; padrão AAA com um Act por teste
6. Garanta determinismo e isolamento (sem dependência de ordem; timeout em I/O)

## Examples

**Rust (integração, padrão test-rust):**
```rust
#[tokio::test]
async fn rls_blocks_cross_tenant_read() -> anyhow::Result<()> {
    // Arrange: dois tenants com dados próprios
    let pool = common::pool_de_teste().await?;
    // Act: tenant B consulta dados do tenant A
    let linhas = consultar_como(&pool, tenant_b, ticket_de_a).await?;
    // Assert: RLS nega — zero linhas, sem erro
    assert!(linhas.is_empty());
    Ok(())
}
```

**Python (pytest async):**
```python
async def test_transcricao_rejeita_mimetype_nao_suportado():
    # Arrange / Act / Assert: valida a variante de erro, não só a falha
    with pytest.raises(AudioFormatError):
        await transcrever_audio(pointer_de_video())
```

**Flutter (widget test):**
```dart
testWidgets('login mostra erro com credenciais inválidas', (tester) async {
  await tester.pumpWidget(app(datasource: RemoteOnlyFake.falhaAuth()));
  await tester.tap(find.byKey(const Key('botao_entrar')));
  await tester.pump();
  expect(find.text('Credenciais inválidas'), findsOneWidget);
});
```

## Quality Bar

- Testar comportamento, não implementação; validar a **variante** do erro (`matches!`), não só `is_err()`
- Rust: organização da skill `test-rust` (inline p/ unitário; `tests/` com agregador p/ integração)
- Mock apenas na fronteira externa; banco/cache/domínio próprios são sempre reais
- Todo bugfix entra com teste de regressão no mesmo PR
- Testes rápidos e determinísticos; integração com `RUST_TEST_THREADS=1` quando há estado compartilhado (Redis DB 15)

## Resource Strategy

- Add `scripts/` only when the task is fragile, repetitive, or benefits from deterministic execution.
- Add `references/` only when details are too large or too variant-specific to keep in `SKILL.md`.
- Add `assets/` only for files that will be consumed in the final output.
- Keep extra docs out of the skill folder; prefer `SKILL.md` plus only the resources that materially help.
