// A situação exibida na lista de vouchers é a única regra de negócio que o
// painel decide sozinho — o resto é o servidor quem diz.
import 'package:admin_module/src/features/billing/domain/model/voucher.dart';
import 'package:flutter_test/flutter_test.dart';

final _agora = DateTime(2026, 7, 31, 12);

Voucher _voucher({
  int maxResgates = 1,
  int resgatesUsados = 0,
  DateTime? validoDe,
  DateTime? validoAte,
  DateTime? revogadoEm,
}) => Voucher(
  id: 'v-1',
  codigo: 'DEVTESTE',
  descricao: '',
  planId: 1,
  planName: 'Básico',
  duracaoDias: 180,
  maxResgates: maxResgates,
  resgatesUsados: resgatesUsados,
  validoDe: validoDe ?? _agora.subtract(const Duration(days: 1)),
  validoAte: validoAte,
  revogadoEm: revogadoEm,
  motivoRevogacao: '',
  createdAt: _agora.subtract(const Duration(days: 2)),
);

void main() {
  group('Voucher.situacaoEm', () {
    test('dentro da janela e com vaga: ativo', () {
      expect(_voucher().situacaoEm(_agora), SituacaoVoucher.ativo);
    });

    test('revogação prevalece sobre expiração', () {
      // Quando as duas se aplicam, o superusuário precisa ver a decisão humana
      // — é ela que explica por que o código parou de funcionar.
      final v = _voucher(
        validoAte: _agora.subtract(const Duration(days: 1)),
        revogadoEm: _agora.subtract(const Duration(hours: 2)),
      );
      expect(v.situacaoEm(_agora), SituacaoVoucher.revogado);
    });

    test('expirado quando a janela fechou', () {
      final v = _voucher(validoAte: _agora.subtract(const Duration(days: 1)));
      expect(v.situacaoEm(_agora), SituacaoVoucher.expirado);
    });

    test('esgotado quando as vagas acabaram', () {
      expect(
        _voucher(maxResgates: 3, resgatesUsados: 3).situacaoEm(_agora),
        SituacaoVoucher.esgotado,
      );
    });

    test('max_resgates 0 é ilimitado — nunca esgota', () {
      final v = _voucher(maxResgates: 0, resgatesUsados: 9999);
      expect(v.esgotado, isFalse);
      expect(v.situacaoEm(_agora), SituacaoVoucher.ativo);
    });

    test('agendado quando a validade ainda não começou', () {
      final v = _voucher(validoDe: _agora.add(const Duration(days: 3)));
      expect(v.situacaoEm(_agora), SituacaoVoucher.agendado);
    });

    test('sem valido_ate não expira sozinho', () {
      expect(_voucher().expiradoEm(_agora.add(const Duration(days: 3650))),
          isFalse);
    });
  });
}
