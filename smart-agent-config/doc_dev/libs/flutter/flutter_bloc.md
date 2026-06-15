# Flutter BLoC (flutter_bloc)

- **Versão Recomendada:** 9.1.1 (par com `bloc ^9.2.1`; API de `Cubit`/`BlocBuilder`/`BlocListener` inalterada vs 8.x — 9.0 removeu apenas `BlocOverrides`)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-14
- **Propósito no Projeto:** Gerenciamento de estado previsível e reativo baseado no padrão BLoC (Business Logic Component) para controlar as interações visuais complexas do Chat e Kanban.
- **Documentação Oficial:** [https://bloclibrary.dev/](https://bloclibrary.dev/)

---

## 1. Contexto e Uso no Projeto

A interface de usuário do Smart Core Assistant v2 possui fluxos com alto volume de atualizações simultâneas (WebSocket enviando novas mensagens enquanto o usuário arrasta tickets no Kanban). 

O **BLoC** é adotado como padrão para separar a UI (Widgets) da lógica de negócios, controlando a emissão de estados de forma estrita e unidirecional:
`Widgets (Disparam Eventos) ──► BLoC (Processa e Emite) ──► Widgets (Reagem ao Estado)`

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Separação Coesa de Arquivos (Bloc, Event, State)
Cada feature complexa no diretório `features/` deve declarar três arquivos dedicados:
1.  `<feature>_event.dart`: Contém a classe base abstrata e os eventos imutáveis de entrada acionados pelo usuário.
2.  `<feature>_state.dart`: Contém os estados imutáveis expostos para a UI reagir (ex: Loading, Success, Error).
3.  `<feature>_bloc.dart`: Classe controladora que escuta eventos e manipula os Use Cases.

*Exemplo para a feature Kanban:*
```dart
// features/kanban/presentation/bloc/kanban_event.dart
abstract class KanbanEvent {}
class LoadKanbanBoard extends KanbanEvent {
  final String tenantId;
  LoadKanbanBoard(this.tenantId);
}
class MoveTicketEvent extends KanbanEvent {
  final String ticketId;
  final String targetStageId;
  MoveTicketEvent(this.ticketId, this.targetStageId);
}

// features/kanban/presentation/bloc/kanban_state.dart
abstract class KanbanState {}
class KanbanLoading extends KanbanState {}
class KanbanLoaded extends KanbanState {
  final List<Stage> stages;
  KanbanLoaded(this.stages);
}
class KanbanError extends KanbanState {
  final String message;
  KanbanError(this.message);
}
```

### 2.2 Implementação do Bloco de Lógica (Bloc)
Associe os eventos às funções de mapeamento usando o método `on<Event>` e injete os repositórios de dados no construtor.

```dart
// features/kanban/presentation/bloc/kanban_bloc.dart
import 'package:flutter_bloc/flutter_bloc.dart';

class KanbanBloc extends Bloc<KanbanEvent, KanbanState> {
  final KanbanRepository _repository;

  KanbanBloc({required KanbanRepository repository})
      : _repository = repository,
        super(KanbanLoading()) {
    on<LoadKanbanBoard>(_onLoadKanbanBoard);
    on<MoveTicketEvent>(_onMoveTicket);
  }

  Future<void> _onLoadKanbanBoard(LoadKanbanBoard event, Emitter<KanbanState> emit) async {
    emit(KanbanLoading());
    try {
      final board = await _repository.fetchBoard(event.tenantId);
      emit(KanbanLoaded(board.stages));
    } catch (e) {
      emit(KanbanError("Falha ao carregar o Kanban: $e"));
    }
  }

  Future<void> _onMoveTicket(MoveTicketEvent event, Emitter<KanbanState> emit) async {
    // Implementa lógica otimista ou de loading local
  }
}
```

### 2.3 Reação na Interface (BlocBuilder e BlocListener)
Utilize `BlocBuilder` para renderizar layouts com base no estado e `BlocListener` para efeitos colaterais de navegação ou alertas (SnackBars).

```dart
Widget build(BuildContext context) {
  return BlocConsumer<KanbanBloc, KanbanState>(
    listener: (context, state) {
      if (state is KanbanError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.message)),
        );
      }
    },
    builder: (context, state) {
      if (state is KanbanLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (state is KanbanLoaded) {
        return KanbanBoardWidget(stages: state.stages);
      }
      return const SizedBox.shrink();
    },
  );
}
```
