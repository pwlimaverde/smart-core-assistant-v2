# connectivity_plus

- **Versão Recomendada:** 6.x (atual 6.1.x+)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-07-18
- **Propósito no Projeto:** Trigger de sincronização por reconexão no desktop (fase N7.4) — o `local_engine_ffi` dispara `sincronizar()` quando a conectividade volta, complementando o timer periódico e o best-effort na abertura da fila.
- **Documentação Oficial:** https://pub.dev/packages/connectivity_plus
- **Library ID Context7:** `/websites/pub_dev_packages_connectivity_plus`

---

## Histórico de Atualizações

- **2026-07-18** — Documentação inicial criada via Context7. Foco no listener `onConnectivityChanged` (retorna `Stream<List<ConnectivityResult>>` desde a v5), `checkConnectivity()` e no **caveat central**: detecta tipo de interface de rede, NÃO garante alcance real da internet.

---

## 1. Instalação

```yaml
# pubspec.yaml
dependencies:
  connectivity_plus: ^6.1.0
```

Plataformas suportadas: Android, iOS, macOS, **Windows**, Linux, Web.

---

## 2. API Central

### Checagem pontual

```dart
import 'package:connectivity_plus/connectivity_plus.dart';

final List<ConnectivityResult> resultado = await Connectivity().checkConnectivity();

if (resultado.contains(ConnectivityResult.none)) {
  // Sem nenhuma interface de rede ativa.
} else {
  // Há wifi / ethernet / mobile / vpn / ...
}
```

> **Mudança de API (v5+):** tanto `checkConnectivity()` quanto o stream passaram a
> devolver **`List<ConnectivityResult>`** (antes era um único valor). O dispositivo
> pode ter várias interfaces ativas simultaneamente.

### Listener de mudanças

```dart
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

StreamSubscription<List<ConnectivityResult>>? _sub;

void iniciar() {
  _sub = Connectivity().onConnectivityChanged.listen((resultados) {
    final online = !resultados.contains(ConnectivityResult.none);
    if (online) {
      // Disparar tentativa de sync (com debounce — ver §3).
    }
  });
}

void dispose() {
  _sub?.cancel(); // sempre cancelar
}
```

`ConnectivityResult`: `wifi`, `ethernet`, `mobile`, `vpn`, `bluetooth`,
`satellite`, `other`, `none`.

---

## 3. Caveat crítico (impacta o uso no N7.4)

⚠️ **`connectivity_plus` reporta o TIPO de interface, não alcance real da internet.**
A doc oficial é explícita: *"this does not guarantee actual internet access"* —
uma rede pode ter interface ativa mas sem saída (captive portal, VPN caindo, DNS
quebrado).

**Consequência para o trigger de sync:**
- Trate o evento de reconexão como um **gatilho oportunista**, não como garantia.
  Ao receber `!= none`, tente `sincronizar()`; se o transporte falhar, a ação
  permanece na fila offline (o design já é resiliente por `action_id`).
- **Nunca** marque ações como sincronizadas com base no evento de conectividade —
  só o retorno real do transporte confirma.

⚠️ **Eventos duplicados/instáveis (iOS/macOS):** com `NWPathMonitor`, o
`onConnectivityChanged` pode emitir múltiplos eventos e **não filtra distintos**.
No Windows o comportamento é mais estável, mas ainda assim aplique **debounce**.

### Padrão recomendado (debounce + guarda anti-concorrência)

```dart
Timer? _debounce;
bool _sincronizando = false; // guarda já existente no LocalEngine

void _onConnectivity(List<ConnectivityResult> r) {
  if (r.contains(ConnectivityResult.none)) return;
  _debounce?.cancel();
  _debounce = Timer(const Duration(seconds: 3), () async {
    if (_sincronizando) return; // não empilhar syncs
    _sincronizando = true;
    try {
      await localEngine.sincronizar(); // falha → ações seguem na fila
    } finally {
      _sincronizando = false;
    }
  });
}
```

---

## 4. Notas de Compatibilidade

- **Windows:** suportado (alvo principal do desktop). Requer o desktop embedding
  padrão do Flutter — sem configuração extra.
- **Web:** funciona, mas o navegador só distingue online/offline (sempre `wifi`/`none`).
- **Sem custo de bateria relevante** quando usado como listener passivo; o problema
  de bateria vem de disparar sync em loop — mitigado pelo debounce.

---

## 5. Referências

| Recurso | Link |
|---------|------|
| Pub.dev | https://pub.dev/packages/connectivity_plus |
| Repositório | https://github.com/fluttercommunity/plus_plugins |
| API docs | https://pub.dev/documentation/connectivity_plus/latest/ |
