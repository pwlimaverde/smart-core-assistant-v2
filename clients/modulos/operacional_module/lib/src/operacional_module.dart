import 'package:core_module/core_module.dart' as core;
import 'package:dependencies_module/dependencies_module.dart';

import 'features/atendimento/data/datasources/platform/atendimento_data_source_factory.dart';
import 'features/atendimento/data/services/atendimento_service_impl.dart';
import 'features/atendimento/domain/datasources/atendimento_data_source.dart';
import 'features/atendimento/domain/services/atendimento_service.dart';
import 'features/atendimento/domain/usecases/get_thread_usecase.dart';
import 'features/atendimento/domain/usecases/list_atendimentos_usecase.dart';
import 'features/atendimento/domain/usecases/move_atendimento_etapa_usecase.dart';
import 'features/atendimento/domain/usecases/send_outbound_message_usecase.dart';
import 'features/atendimento/presentation/routes/kanban_route.dart';

/// Módulo Operacional (fila/Kanban/chat — WS-6): registra a implementação
/// RemoteOnly do [AtendimentoDataSource] (gRPC-Web) e contribui a rota
/// '/atendimentos'.
///
/// **Ports & Adapters:** telas/controllers dependem SOMENTE de
/// [AtendimentoDataSource]/[AtendimentoService] via `get_it` — nunca do stub
/// gRPC direto. O adapter concreto é escolhido por import condicional: Web usa o
/// RemoteOnly (gRPC-Web), o desktop usa o motor local via FFI. Nenhuma tela muda.
final class OperacionalModule extends AppModule {
  @override
  void globalBinds(Injector i) {
    // Adapter do port escolhido por plataforma (Web: gRPC-Web; desktop: FFI).
    // O `AdminServiceClient` (do GrpcTransport global) serve o Web hoje e o
    // transporte de sync do desktop amanhã; o tenant vem da sessão.
    i.lazySingleton<AtendimentoDataSource>(() {
      final client = inject<ApiClient>();
      if (client is! GrpcTransport) {
        throw StateError('ApiClient não é do tipo GrpcTransport esperado.');
      }
      return createAtendimentoDataSource(
        adminClient: client.admin,
        tenantIdProvider: () => inject<core.SessionService>().tenantId,
      );
    });

    i.lazySingleton<AtendimentoService>(
      () => AtendimentoServiceImpl(datasource: inject<AtendimentoDataSource>()),
    );

    i.lazySingleton<ListAtendimentosUsecase>(
      () => ListAtendimentosUsecase(service: inject<AtendimentoService>()),
    );
    i.lazySingleton<GetThreadUsecase>(
      () => GetThreadUsecase(service: inject<AtendimentoService>()),
    );
    i.lazySingleton<MoveAtendimentoEtapaUsecase>(
      () => MoveAtendimentoEtapaUsecase(service: inject<AtendimentoService>()),
    );
    i.lazySingleton<SendOutboundMessageUsecase>(
      () => SendOutboundMessageUsecase(service: inject<AtendimentoService>()),
    );
  }

  @override
  List<GetItModule> routes() => [KanbanRoute()];
}
