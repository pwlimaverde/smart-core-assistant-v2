import 'package:api_client/api_client.dart' as proto;
import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/data/gateways/analise_do_proto.dart';

void main() {
  test('servidor sem a análise deixa a seção vazia', () {
    final analise = analiseDoProto(proto.DetalheAtendimentoResponse());

    expect(analise.vazia, isTrue);
  });

  test('converte intenções, entidades, sentimento e a última decisão', () {
    final resp = proto.DetalheAtendimentoResponse(
      analise: proto.AnaliseDaConversa(
        intencoes: [
          proto.IntencaoDaConversa(
            tipo: 'coleta_dados_panfleto',
            confianca: 0.83,
            vezes: 2,
          ),
        ],
        entidades: [
          proto.EntidadeDaConversa(tipo: 'quantidade', valor: '2000'),
        ],
        sentimentoLabel: 'neutro',
        sentimentoNota: 3,
        ultimaDecisao: proto.DecisaoDaConversa(
          motor: 'jev',
          ato: 'coletar',
          motivo: 'coleta',
        ),
      ),
    );

    final analise = analiseDoProto(resp);

    expect(analise.vazia, isFalse);
    expect(analise.intencoes.single.tipo, 'coleta_dados_panfleto');
    expect(analise.intencoes.single.vezes, 2);
    expect(analise.entidades.single.valor, '2000');
    expect(analise.sentimentoNota, 3);
    expect(analise.ultimaDecisao?.ato, 'coletar');
    expect(analise.ultimaDecisao?.motor, 'jev');
  });

  test('decisão antiga sem ato usa a decisão', () {
    final resp = proto.DetalheAtendimentoResponse(
      analise: proto.AnaliseDaConversa(
        ultimaDecisao: proto.DecisaoDaConversa(
          motor: 'jev',
          decisao: 'transferida',
          transferiu: true,
        ),
      ),
    );

    expect(analiseDoProto(resp).ultimaDecisao?.ato, 'transferida');
  });
}
