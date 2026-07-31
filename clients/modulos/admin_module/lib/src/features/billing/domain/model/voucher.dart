import 'package:meta/meta.dart';

/// Código de ativação de assinatura.
///
/// **Não é cupom de desconto:** o voucher não abate valor, ele concede um plano
/// por um período. É o meio de pagamento usado enquanto não há gateway, e
/// continua útil depois — cortesias, testes, migração de cliente.
@immutable
class Voucher {
  final String id;
  final String codigo;
  final String descricao;
  final int planId;
  final String planName;
  final int duracaoDias;

  /// 0 = ilimitado.
  final int maxResgates;
  final int resgatesUsados;
  final DateTime validoDe;

  /// `null` = não expira sozinho.
  final DateTime? validoAte;

  /// `null` = não revogado.
  final DateTime? revogadoEm;
  final String motivoRevogacao;
  final DateTime createdAt;

  const Voucher({
    required this.id,
    required this.codigo,
    required this.descricao,
    required this.planId,
    required this.planName,
    required this.duracaoDias,
    required this.maxResgates,
    required this.resgatesUsados,
    required this.validoDe,
    required this.validoAte,
    required this.revogadoEm,
    required this.motivoRevogacao,
    required this.createdAt,
  });

  bool get revogado => revogadoEm != null;

  bool get esgotado => maxResgates != 0 && resgatesUsados >= maxResgates;

  bool expiradoEm(DateTime agora) =>
      validoAte != null && agora.isAfter(validoAte!);

  /// Situação para exibir na lista. A ordem das checagens define qual prevalece
  /// quando mais de uma se aplica — revogado ganha, porque é decisão de um
  /// humano, e é o que o superusuário precisa ver em primeiro lugar.
  SituacaoVoucher situacaoEm(DateTime agora) {
    if (revogado) return SituacaoVoucher.revogado;
    if (expiradoEm(agora)) return SituacaoVoucher.expirado;
    if (esgotado) return SituacaoVoucher.esgotado;
    if (agora.isBefore(validoDe)) return SituacaoVoucher.agendado;
    return SituacaoVoucher.ativo;
  }
}

/// Situação de um voucher na listagem.
enum SituacaoVoucher {
  ativo,
  agendado,
  esgotado,
  expirado,
  revogado;

  String get rotulo => switch (this) {
    SituacaoVoucher.ativo => 'Ativo',
    SituacaoVoucher.agendado => 'Agendado',
    SituacaoVoucher.esgotado => 'Esgotado',
    SituacaoVoucher.expirado => 'Expirado',
    SituacaoVoucher.revogado => 'Revogado',
  };
}

/// Um resgate registrado: quem usou o voucher e o que recebeu.
@immutable
class VoucherRedemption {
  final String id;
  final String voucherId;
  final String tenantId;
  final int planId;
  final DateTime periodoInicio;
  final DateTime periodoFim;
  final String ip;
  final DateTime redeemedAt;

  const VoucherRedemption({
    required this.id,
    required this.voucherId,
    required this.tenantId,
    required this.planId,
    required this.periodoInicio,
    required this.periodoFim,
    required this.ip,
    required this.redeemedAt,
  });
}
