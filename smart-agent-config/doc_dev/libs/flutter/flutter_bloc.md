# Flutter BLoC (flutter_bloc)

- **Versão Recomendada:** 9.1.1 (par com `bloc ^9.2.1`; API de `Cubit`/`BlocBuilder`/`BlocListener` inalterada vs 8.x — 9.0 removeu apenas `BlocOverrides`)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-10-01
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

### 2.4 Emit, isClosed e Ciclo de Vida

O método `emit()` é usado para emitir novos estados. Porém, **emitir após `close()` gera erro**. Para evitar isso:

```dart
Future<void> _onSomeEvent(SomeEvent event, Emitter<State> emit) async {
  if (isClosed) return; // Guarda: bloc já foi descartado
  
  emit(LoadingState());
  
  try {
    final data = await _repository.fetch();
    if (!isClosed) { // Verificar novamente antes de emit assíncrono
      emit(SuccessState(data));
    }
  } catch (e) {
    if (!isClosed) {
      emit(ErrorState(e.toString()));
    }
  }
}
```

**Melhor prática:** Use `isClosed` para guardar emits em operações assíncronas prolongadas, evitando erros ao descartar o BLoC durante requisições pendentes.

### 2.5 Filtragem com buildWhen e listenWhen

Para evitar rebuilds desnecessários quando chegam múltiplos eventos por mensagem:

```dart
BlocBuilder<KanbanBloc, KanbanState>(
  buildWhen: (previous, current) {
    // Só reconstrói se o estado for diferente (não apenas emitido novamente)
    return previous.hashCode != current.hashCode;
  },
  builder: (context, state) {
    return KanbanBoardWidget(stages: state.stages);
  },
)

BlocListener<KanbanBloc, KanbanState>(
  listenWhen: (previous, current) {
    // Só dispara listener se houver mudança relevante
    return current is KanbanError;
  },
  listener: (context, state) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(state.message)),
    );
  },
)
```

### 2.6 Transformers e Debounce com bloc_concurrency

Para evitar múltiplos eventos de rede quando chegam vários eventos rapidamente:

```dart
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:stream_transform/stream_transform.dart';

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  SearchBloc() : super(SearchInitial()) {
    on<SearchQueryChanged>(
      _onSearchQueryChanged,
      transformer: debounceDroppable(const Duration(milliseconds: 300)),
    );
  }

  Future<void> _onSearchQueryChanged(
    SearchQueryChanged event,
    Emitter<SearchState> emit,
  ) async {
    emit(SearchLoading());
    try {
      final results = await _repository.search(event.query);
      emit(SearchSuccess(results));
    } catch (e) {
      emit(SearchError(e.toString()));
    }
  }
}
```

**Transformers disponíveis:**
- `debounceDroppable()` — aguarda N ms antes de processar; cancela anteriores
- `throttleDroppable()` — processa apenas 1 evento a cada N ms
- `restartable()` — cancela anterior e reinicia ao novo evento
- `concurrent()` — processa sem cancelar

### 2.7 Distinct e Equatable

Para evitar emits de estado duplicado:

```dart
import 'package:equatable/equatable.dart';

class MyState extends Equatable {
  final List<Item> items;
  
  const MyState({required this.items});
  
  @override
  List<Object?> get props => [items]; // Compara por valor, não referência
}

// No BLoC:
Future<void> _onLoad(LoadEvent event, Emitter<MyState> emit) async {
  emit(const MyState(items: [])); // distinct ignora emit idêntico
  final items = await _repository.fetch();
  emit(MyState(items: items)); // Emite sempre (lista nova)
}
```

---

## 3. Histórico de Atualizações

| Versão | Data | Motivo |
|--------|------|--------|
| 9.1.1 | 2026-10-01 | Verificado: versão estável; bloc ^9.2.1 compatível; adicionadas seções sobre emit/isClosed, buildWhen/listenWhen, transformers com bloc_concurrency e Equatable |
