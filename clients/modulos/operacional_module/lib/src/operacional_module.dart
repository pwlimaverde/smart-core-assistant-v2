import 'package:core_module/core_module.dart' as core;
import 'package:dependencies_module/dependencies_module.dart';

import 'features/atendimento/data/datasources/atendimento_datasources.dart';
import 'features/atendimento/data/gateways/platform/atendimento_gateway_factory.dart';
import 'features/atendimento/data/repositories/atendimento_repositories.dart';
import 'features/atendimento/data/streams/atendimento_evento_stream_impl.dart';
import 'features/atendimento/domain/gateways/atendimento_gateway.dart';
import 'features/atendimento/domain/streams/atendimento_evento_stream.dart';
import 'features/atendimento/domain/usecases/atendimento_usecases.dart';
import 'features/atendimento/presentation/routes/kanban_route.dart';

/// Módulo Operacional (fila/Kanban/chat — WS-6): monta a cadeia
/// `Gateway → Datasource → Repository → Usecase` e contribui a rota
/// '/atendimentos'.
///
/// **Dois eixos de variação, dois papéis:** o [AtendimentoGateway] varia por
/// **plataforma** (gRPC-Web no browser, motor local Rust no desktop, escolhido
/// por import condicional); os `Datasource` variam por **operação** e ficam em
/// cima dele. Telas e controllers não conhecem nenhum dos dois — dependem só dos
/// usecases e do port de eventos.
final class OperacionalModule extends AppModule {
  @override
  void globalBinds(Injector i) {
    // Fronteira de infraestrutura, uma por plataforma. O `AdminServiceClient`
    // (do GrpcTransport global) serve o Web hoje e o transporte de sync do
    // desktop; o tenant vem da sessão.
    i.lazySingleton<AtendimentoGateway>(() {
      final client = inject<ApiClient>();
      if (client is! GrpcTransport) {
        throw StateError('ApiClient não é do tipo GrpcTransport esperado.');
      }
      return createAtendimentoGateway(
        adminClient: client.admin,
        tenantIdProvider: () => inject<core.SessionService>().tenantId,
      );
    });

    i.lazySingleton<AtendimentoEventoStream>(
      () => AtendimentoEventoStreamImpl(gateway: inject<AtendimentoGateway>()),
    );

    i.lazySingleton<ListAtendimentosUsecase>(
      () => ListAtendimentosUsecase(
        repository: ListAtendimentosRepository(
          datasource: ListAtendimentosDatasource(
            gateway: inject<AtendimentoGateway>(),
          ),
        ),
      ),
    );
    i.lazySingleton<GetThreadUsecase>(
      () => GetThreadUsecase(
        repository: GetThreadRepository(
          datasource: GetThreadDatasource(
            gateway: inject<AtendimentoGateway>(),
          ),
        ),
      ),
    );
    i.lazySingleton<MoveAtendimentoEtapaUsecase>(
      () => MoveAtendimentoEtapaUsecase(
        repository: MoveAtendimentoEtapaRepository(
          datasource: MoveAtendimentoEtapaDatasource(
            gateway: inject<AtendimentoGateway>(),
          ),
        ),
      ),
    );
    i.lazySingleton<SendOutboundMessageUsecase>(
      () => SendOutboundMessageUsecase(
        repository: SendOutboundMessageRepository(
          datasource: SendOutboundMessageDatasource(
            gateway: inject<AtendimentoGateway>(),
          ),
        ),
      ),
    );
  }

  @override
  List<GetItModule> routes() => [KanbanRoute()];
}
