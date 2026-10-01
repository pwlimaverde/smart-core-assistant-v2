import 'package:api_client/api_client.dart' as proto;

import '../../domain/model/ficha.dart';

/// A análise da IA da ficha, do proto para o modelo. Usada pelos dois
/// gateways (Web e desktop), que montam a ficha da mesma resposta.
AnaliseDaIa analiseDoProto(proto.DetalheAtendimentoResponse resp) {
  if (!resp.hasAnalise()) return const AnaliseDaIa();
  final a = resp.analise;
  final d = a.hasUltimaDecisao() ? a.ultimaDecisao : null;
  return AnaliseDaIa(
    intencoes: [
      for (final i in a.intencoes)
        (tipo: i.tipo, confianca: i.confianca, vezes: i.vezes),
    ],
    entidades: [
      for (final e in a.entidades)
        (tipo: e.tipo, valor: e.valor, confianca: e.confianca),
    ],
    sentimentoLabel: a.sentimentoLabel,
    sentimentoNota: a.sentimentoNota,
    ultimaDecisao: d == null
        ? null
        : (
            motor: d.motor,
            ato: d.ato.isNotEmpty ? d.ato : d.decisao,
            motivo: d.motivo,
            transferiu: d.transferiu,
          ),
  );
}
