import 'package:return_success_or_error/return_success_or_error.dart';

/// Parâmetros para mover um atendimento de etapa no Kanban (drag-and-drop —
/// WS-6.2). O RBAC fino por fluxo (`flow_permissions`, WS-5a) é aplicado
/// 100% server-side; aqui só carregamos a intenção do usuário.
final class MoveAtendimentoEtapaParameters extends Parameters {
  final int atendimentoId;
  final int etapaDestinoId;
  final String motivo;

  const MoveAtendimentoEtapaParameters({
    required this.atendimentoId,
    required this.etapaDestinoId,
    this.motivo = '',
  });
}
