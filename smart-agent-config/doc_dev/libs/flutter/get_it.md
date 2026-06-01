# Get It

- **Versão Recomendada:** 7.6.0
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
- **Propósito no Projeto:** Service Locator simples e rápido para injeção de dependências (Repositories, DataSources, Serviços e ViewModels) no frontend Flutter.
- **Documentação Oficial:** [https://pub.dev/packages/get_it](https://pub.dev/packages/get_it)

---

## 1. Contexto e Uso no Projeto

No frontend do Smart Core Assistant v2, a arquitetura deve obedecer ao princípio de desacoplamento de infraestrutura. Os Widgets da interface do usuário e os controladores de estado (ViewModels) nunca devem instanciar diretamente as origens de dados.

O **Get It** atua como o contêiner central que resolve as dependências a partir do bootstrapping do aplicativo.

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Configuração Centralizada de Dependências (di.dart)
Toda a fiação de injeção de dependências do aplicativo deve residir em um único arquivo sob `lib/app/di.dart`. As dependências devem ser registradas no método `setupDependencyInjection()` que é aguardado na inicialização da função `main()`.

```dart
// lib/app/di.dart
import 'package:get_it/get_it.dart';

final GetIt locator = GetIt.instance;

void setupDependencyInjection() {
  // 1. Registrar Fontes de Dados (DataSources)
  // Dependendo do ambiente, registra FFI ou RemoteOnly
  if (isWindowsDesktop) {
    locator.registerLazySingleton<DataSource>(() => LocalEngineDataSource());
  } else {
    locator.registerLazySingleton<DataSource>(() => RemoteOnlyDataSource());
  }

  // 2. Registrar Repositórios dependendo da abstração DataSource
  locator.registerLazySingleton<KanbanRepository>(
    () => KanbanRepositoryImpl(dataSource: locator<DataSource>()),
  );

  // 3. Registrar ViewModels/Controllers (Fabricas)
  locator.registerFactory<KanbanController>(
    () => KanbanController(repository: locator<KanbanRepository>()),
  );
}
```

### 2.2 Dependência de Contratos Abstratos (Interfaces)
Sempre registre e recupere dependências utilizando a interface abstrata como tipo Genérico, e nunca a classe de implementação concreta. Isso permite alternar as implementações dinamicamente (ex: FFI vs Web) sem quebrar o restante do código.

*   **Incorreto (Não Faça):**
    ```dart
    // Acoplamento com classe concreta impossibilita port Web
    final repo = locator<LocalEngineKanbanRepository>(); 
    ```
*   **Correto (Faça):**
    ```dart
    // Depende apenas do contrato abstrato
    final repo = locator<KanbanRepository>();
    ```

### 2.3 Substituição Simples em Testes Unitários
O uso de injeção via construtor é o método preferencial para testar ViewModels e Repositórios. No entanto, se precisar testar componentes visuais (Widget Tests) que chamam dependências globais via `locator`, limpe e reinscreva as dependências com mocks antes de inflar o Widget:

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    // Limpa o contêiner antes de cada teste de integração/widget
    locator.reset();
  });

  testWidgets('should render board when KanbanRepository is injected', (tester) async {
    // Arrange
    final mockRepo = MockKanbanRepository();
    // Força o retorno mockado
    when(() => mockRepo.fetchStages()).thenAnswer((_) async => []);

    // Registra o mock no locator
    locator.registerSingleton<KanbanRepository>(mockRepo);

    // Act
    await tester.pumpWidget(const MyKanbanApp());

    // Assert
    expect(find.byType(KanbanBoardWidget), findsOneWidget);
  });
}
```
