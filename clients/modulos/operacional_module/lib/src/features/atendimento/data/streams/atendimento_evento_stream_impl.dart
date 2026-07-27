import '../../domain/gateways/atendimento_gateway.dart';
import '../../domain/model/atendimento_evento.dart';
import '../../domain/streams/atendimento_evento_stream.dart';

/// Implementação do port de eventos: delega ao gateway da plataforma ativa
/// (gRPC-Web no browser, motor local no desktop).
///
/// Fina de propósito — existe para que os controllers dependam de um port de
/// domínio em vez do gateway de infraestrutura, mantendo a mesma direção de
/// dependência das outras quatro operações.
final class AtendimentoEventoStreamImpl implements AtendimentoEventoStream {
  final AtendimentoGateway _gateway;

  const AtendimentoEventoStreamImpl({required this._gateway});

  @override
  Stream<AtendimentoEvento> abrir() => _gateway.streamAtendimentos();
}
