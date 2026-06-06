# Mocktail

- **Versão Recomendada:** 1.0.4
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
- **Propósito no Projeto:** Framework de mocking declarativo e simples para testes unitários e de widgets em Dart/Flutter.
- **Documentação Oficial:** [https://pub.dev/packages/mocktail](https://pub.dev/packages/mocktail)

---

## 1. Contexto e Uso no Projeto

No frontend do Smart Core Assistant v2, a testabilidade das classes e widgets é garantida pelo desacoplamento total de dependências nativas (Rust FFI) e de rede. 

O **Mocktail** é utilizado para simular o comportamento de chamadas de rede ou interações nativas da FFI de forma segura e controlável nos testes unitários (`test/unit/`) e testes de widgets (`test/widgets/`).

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Mocks de Interfaces Limpos
Sempre crie classes de mock herdando de `Mock` e implementando a interface da dependência que deseja isolar.

```dart
import 'package:mocktail/mocktail.dart';
import 'package:flutter_test/flutter_test.dart';

// Definindo os mocks
class MockDataSource extends Mock implements DataSource {}
class MockKanbanRepository extends Mock implements KanbanRepository {}
```

### 2.2 Uso correto de `when` e `verify`
Siga a estrutura Arrange-Act-Assert nos testes unitários:

```dart
void main() {
  late MockKanbanRepository mockRepository;
  late KanbanController controller;

  setUp(() {
    mockRepository = MockKanbanRepository();
    controller = KanbanController(repository: mockRepository);
  });

  test('should emit success status when ticket is moved successfully', () async {
    // Arrange (Preparar comportamento do Mock)
    when(() => mockRepository.moveTicket('ticket-1', 'stage-2'))
        .thenAnswer((_) async => true); // Usa thenAnswer para retorno de Future

    // Act (Executar a ação)
    await controller.moveTicket('ticket-1', 'stage-2');

    // Assert (Validar alterações de estado e chamadas)
    expect(controller.state.status, KanbanStatus.success);
    
    // Verifica que a dependência foi invocada exatamente 1 vez com os argumentos corretos
    verify(() => mockRepository.moveTicket('ticket-1', 'stage-2')).called(1);
  });
}
```

### 2.3 Registro de Parâmetros Customizados (registerFallbackValue)
Se o método mocado receber um objeto customizado (instância de uma classe de domínio complexa, ex: `Ticket` ou um Enum customizado), registre um fallback para permitir o casamento genérico de parâmetros (`any()`).

```dart
class MockTicket extends Mock implements Ticket {}

void main() {
  setUpAll(() {
    // Registra um fallback genérico para que any() funcione com esse tipo
    registerFallbackValue(Ticket(id: 'dummy', subject: ''));
  });

  test('should save ticket when repository is invoked', () async {
    when(() => mockRepository.saveTicket(any()))
        .thenAnswer((_) async => true);
        
    // Executa...
  });
}
```

### 2.4 Isolamento Absoluto de Dependências Rust
*   **Nunca** teste a integração nativa FFI compilada (`.dll`/`.so`) dentro de testes unitários do Flutter.
*   Moque a interface `DataSource` inteira. Testar se o Crate Rust funciona isoladamente é responsabilidade da suite de testes de integração do próprio Rust (`cargo test`), e não dos testes do Flutter.
