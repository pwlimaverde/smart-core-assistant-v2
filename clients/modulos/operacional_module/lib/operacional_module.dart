/// Módulo Operacional (fila/Kanban/chat — WS-6).
///
/// Expõe o módulo (composição no bootstrap), os modelos de domínio que outras
/// camadas consomem e a rota do Kanban. O gateway de plataforma, os datasources,
/// os repositórios e os usecases são detalhe interno de `src/`.
library;

export 'src/features/atendimento/domain/errors/atendimento_errors.dart';
export 'src/features/atendimento/domain/model/atendimento_evento.dart';
export 'src/features/atendimento/domain/model/atendimento_resumo.dart';
export 'src/features/atendimento/domain/model/mensagem_thread.dart';
export 'src/features/atendimento/domain/streams/atendimento_evento_stream.dart';
export 'src/features/atendimento/presentation/routes/kanban_route.dart';
export 'src/operacional_module.dart';
// C3: o app do tenant fornece a busca de clientes ao quadro; para isso precisa
// enxergar o formato reduzido que o diálogo consome.
export 'src/features/atendimento/domain/model/contato_para_atendimento.dart'
    show BuscarContatos, ContatoParaAtendimento;
