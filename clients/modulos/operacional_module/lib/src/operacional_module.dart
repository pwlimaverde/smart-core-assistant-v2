import 'package:api_client/grpc_web_client.dart';
import 'package:dependencies_module/dependencies_module.dart';

import 'features/atendimento/data/datasources/atendimento_remote_data_source.dart';
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
/// gRPC direto. Trocar por `LocalEngineFFI` (Windows/F8) exige só um novo
/// binding aqui, sem tocar nenhuma tela.
final class OperacionalModule extends AppModule {
  @override
  void globalBinds(Injector i) {
    // Datasource RemoteOnly (gRPC-Web) — reaproveita o AdminServiceClient já
    // exposto pelo GrpcApiClient global (mesma borda usada pelo admin_module).
    i.lazySingleton<AtendimentoDataSource>(() {
      final client = inject<ApiClient>();
      if (client is GrpcApiClient) {
        return AtendimentoRemoteDataSource(client: client.admin);
      }
      throw StateError('ApiClient não é do tipo GrpcApiClient esperado.');
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
