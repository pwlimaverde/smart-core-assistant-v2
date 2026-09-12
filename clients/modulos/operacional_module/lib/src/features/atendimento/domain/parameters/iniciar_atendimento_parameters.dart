import 'package:return_success_or_error/return_success_or_error.dart';

/// C3 — abrir um atendimento a partir de um cliente já cadastrado.
///
/// [fluxoId] e [etapaInicialId] são obrigatórios, ao contrário da conversa que
/// chega pelo WhatsApp (que nasce sem etapa e é encaixada depois). Um
/// atendimento sem etapa não aparece em coluna nenhuma do quadro — nasceria
/// invisível, que para algo que alguém acabou de abrir é o pior desfecho.
final class IniciarAtendimentoParameters extends Parameters {
  final int contatoId;
  final int fluxoId;
  final int etapaInicialId;
  final int? departamentoId;
  final String? assunto;

  const IniciarAtendimentoParameters({
    required this.contatoId,
    required this.fluxoId,
    required this.etapaInicialId,
    this.departamentoId,
    this.assunto,
  });
}
