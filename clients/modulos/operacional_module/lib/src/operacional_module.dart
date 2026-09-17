import 'features/atendimento/domain/model/contato_para_atendimento.dart';
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
  /// Menu lateral do app hospedeiro, repassado ao quadro.
  ///
  /// O quadro é a primeira tela depois do login; sem menu, a pessoa ficava
  /// presa nele sem caminho para nenhuma configuração. O menu mora no app do
  /// tenant, e este módulo não o conhece — por isso ele entra por parâmetro em
  /// vez de virar uma dependência ao contrário.
  final Widget Function()? drawerBuilder;

  /// Faixa de aviso no topo do quadro — hoje, WhatsApp fora do ar. Entra por
  /// parâmetro pelo mesmo motivo do menu: conexão é assunto do `tenant_module`,
  /// e este módulo não o conhece.
  final Widget Function()? avisoBuilder;

  /// C3 — como o quadro procura clientes para abrir uma conversa. Entra por
  /// parâmetro pelo mesmo motivo dos outros dois: cadastro de contato é do
  /// `tenant_module`, e este módulo não o conhece.
  final BuscarContatos? buscarContatos;

  /// B5 — id do usuário logado, para o quadro avisar quando o rodízio lhe
  /// atribui uma conversa. Por parâmetro pelo mesmo motivo dos outros: a
  /// sessão é do `login_module`, e este módulo não o conhece. Sem ele, o
  /// quadro só não avisa.
  final int? Function()? usuarioAtual;

  OperacionalModule({
    this.drawerBuilder,
    this.avisoBuilder,
    this.buscarContatos,
    this.usuarioAtual,
  });

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
    i.lazySingleton<ListFluxosUsecase>(
      () => ListFluxosUsecase(
        repository: ListFluxosRepository(
          datasource: ListFluxosDatasource(
            gateway: inject<AtendimentoGateway>(),
          ),
        ),
      ),
    );
    i.lazySingleton<ListColunasUsecase>(
      () => ListColunasUsecase(
        repository: ListColunasRepository(
          datasource: ListColunasDatasource(
            gateway: inject<AtendimentoGateway>(),
          ),
        ),
      ),
    );
    i.lazySingleton<SetAtendimentoStatusUsecase>(
      () => SetAtendimentoStatusUsecase(
        repository: SetAtendimentoStatusRepository(
          datasource: SetAtendimentoStatusDatasource(
            gateway: inject<AtendimentoGateway>(),
          ),
        ),
      ),
    );
    i.lazySingleton<ListarTimelineUsecase>(
      () => ListarTimelineUsecase(
        repository: ListarTimelineRepository(
          datasource: ListarTimelineDatasource(
            gateway: inject<AtendimentoGateway>(),
          ),
        ),
      ),
    );
    i.lazySingleton<AtendimentosDoContatoUsecase>(
      () => AtendimentosDoContatoUsecase(
        repository: AtendimentosDoContatoRepository(
          datasource: AtendimentosDoContatoDatasource(
            gateway: inject<AtendimentoGateway>(),
          ),
        ),
      ),
    );
    i.lazySingleton<RemoverNotaUsecase>(
      () => RemoverNotaUsecase(
        repository: RemoverNotaRepository(
          datasource: RemoverNotaDatasource(
            gateway: inject<AtendimentoGateway>(),
          ),
        ),
      ),
    );
    i.lazySingleton<AtualizarEtiquetaUsecase>(
      () => AtualizarEtiquetaUsecase(
        repository: AtualizarEtiquetaRepository(
          datasource: AtualizarEtiquetaDatasource(
            gateway: inject<AtendimentoGateway>(),
          ),
        ),
      ),
    );
    i.lazySingleton<DesativarEtiquetaUsecase>(
      () => DesativarEtiquetaUsecase(
        repository: DesativarEtiquetaRepository(
          datasource: DesativarEtiquetaDatasource(
            gateway: inject<AtendimentoGateway>(),
          ),
        ),
      ),
    );
    i.lazySingleton<AtribuirAtendimentoUsecase>(
      () => AtribuirAtendimentoUsecase(
        repository: AtribuirAtendimentoRepository(
          datasource: AtribuirAtendimentoDatasource(
            gateway: inject<AtendimentoGateway>(),
          ),
        ),
      ),
    );
    i.lazySingleton<DefinirPrioridadeUsecase>(
      () => DefinirPrioridadeUsecase(
        repository: DefinirPrioridadeRepository(
          datasource: DefinirPrioridadeDatasource(
            gateway: inject<AtendimentoGateway>(),
          ),
        ),
      ),
    );
    i.lazySingleton<TransferirParaFluxoUsecase>(
      () => TransferirParaFluxoUsecase(
        repository: TransferirParaFluxoRepository(
          datasource: TransferirParaFluxoDatasource(
            gateway: inject<AtendimentoGateway>(),
          ),
        ),
      ),
    );
    i.lazySingleton<ExportarQuadroUsecase>(
      () => ExportarQuadroUsecase(
        repository: ExportarQuadroRepository(
          datasource: ExportarQuadroDatasource(
            gateway: inject<AtendimentoGateway>(),
          ),
        ),
      ),
    );
    i.lazySingleton<EnviarMidiaUsecase>(
      () => EnviarMidiaUsecase(
        repository: EnviarMidiaRepository(
          datasource: EnviarMidiaDatasource(
            gateway: inject<AtendimentoGateway>(),
          ),
        ),
      ),
    );
    i.lazySingleton<EnviarPresencaUsecase>(
      () => EnviarPresencaUsecase(
        repository: EnviarPresencaRepository(
          datasource: EnviarPresencaDatasource(
            gateway: inject<AtendimentoGateway>(),
          ),
        ),
      ),
    );
    i.lazySingleton<ListarMidiasUsecase>(
      () => ListarMidiasUsecase(
        repository: ListarMidiasRepository(
          datasource: ListarMidiasDatasource(
            gateway: inject<AtendimentoGateway>(),
          ),
        ),
      ),
    );
    i.lazySingleton<GetFichaUsecase>(
      () => GetFichaUsecase(
        repository: GetFichaRepository(
          datasource: GetFichaDatasource(gateway: inject<AtendimentoGateway>()),
        ),
      ),
    );
    i.lazySingleton<CriarEtiquetaUsecase>(
      () => CriarEtiquetaUsecase(
        repository: CriarEtiquetaRepository(
          datasource: CriarEtiquetaDatasource(
            gateway: inject<AtendimentoGateway>(),
          ),
        ),
      ),
    );
    i.lazySingleton<AlternarEtiquetaUsecase>(
      () => AlternarEtiquetaUsecase(
        repository: AlternarEtiquetaRepository(
          datasource: AlternarEtiquetaDatasource(
            gateway: inject<AtendimentoGateway>(),
          ),
        ),
      ),
    );
    i.lazySingleton<MarcarAtendimentoLidoUsecase>(
      () => MarcarAtendimentoLidoUsecase(
        repository: MarcarAtendimentoLidoRepository(
          datasource: MarcarAtendimentoLidoDatasource(
            gateway: inject<AtendimentoGateway>(),
          ),
        ),
      ),
    );
    i.lazySingleton<DefinirBotDaConversaUsecase>(
      () => DefinirBotDaConversaUsecase(
        repository: DefinirBotDaConversaRepository(
          datasource: DefinirBotDaConversaDatasource(
            gateway: inject<AtendimentoGateway>(),
          ),
        ),
      ),
    );
    i.lazySingleton<CriarNotaUsecase>(
      () => CriarNotaUsecase(
        repository: CriarNotaRepository(
          datasource: CriarNotaDatasource(
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

    // N9 E13 — preencher um campo do cartão. Fica no operacional, e não no
    // tenant_module com o catálogo: desenhar o campo é configuração,
    // preenchê-lo é atendimento — quem está na conversa é quem sabe o valor.
    i.lazySingleton<DefinirValorCampoUsecase>(
      () => DefinirValorCampoUsecase(
        repository: DefinirValorCampoRepository(
          datasource: DefinirValorCampoDatasource(
            gateway: inject<AtendimentoGateway>(),
          ),
        ),
      ),
    );

    // C3 — abrir conversa a partir de um cliente cadastrado. Faltava aqui: os
    // testes do diálogo registram o usecase direto no GetIt, e por isso
    // passavam enquanto o app estourava no primeiro clique em "Abrir conversa".
    i.lazySingleton<IniciarAtendimentoUsecase>(
      () => IniciarAtendimentoUsecase(
        repository: IniciarAtendimentoRepository(
          datasource: IniciarAtendimentoDatasource(
            gateway: inject<AtendimentoGateway>(),
          ),
        ),
      ),
    );
  }

  @override
  List<GetItModule> routes() => [
    KanbanRoute(
      drawerBuilder: drawerBuilder,
      avisoBuilder: avisoBuilder,
      buscarContatos: buscarContatos,
      usuarioAtual: usuarioAtual,
    ),
  ];
}
