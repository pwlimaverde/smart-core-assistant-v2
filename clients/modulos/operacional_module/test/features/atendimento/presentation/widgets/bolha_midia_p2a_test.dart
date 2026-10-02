import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/mensagem_thread.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/midia_mensagem.dart';
import 'package:operacional_module/src/features/atendimento/presentation/widgets/chat_message_bubble.dart';
import 'package:operacional_module/src/features/atendimento/presentation/widgets/midia_da_bolha.dart';

/// P2a — a bolha desenha o anexo por tipo. Nenhum teste aqui toca mídia: o
/// `Player` do áudio só nasce no primeiro "play" e o do vídeo só no diálogo,
/// e nenhum dos dois é acionado — o libmpv não existe no ambiente de teste.

const _url = 'https://r2.exemplo/media/t/i/x/abc?X-Amz-Signature=sig';

MidiaMensagem _midia(
  TipoMidia tipo, {
  String mimetype = 'application/octet-stream',
  String nome = 'arquivo.bin',
  int bytes = 0,
  int? segundos,
  bool ptt = false,
  String url = _url,
}) => MidiaMensagem(
  tipo: tipo,
  urlAssinada: url,
  mimetype: mimetype,
  nomeArquivo: nome,
  tamanhoBytes: bytes,
  segundos: segundos,
  ehPtt: ptt,
);

MensagemThread _mensagem(MidiaMensagem? midia, {String conteudo = ''}) =>
    MensagemThread(
      id: 7,
      atendimentoId: 1,
      tipo: 'midia',
      conteudo: conteudo,
      remetente: 'usuario',
      timestamp: DateTime(2026, 1, 1, 10, 30),
      statusEnvio: 'sent',
      midia: midia,
    );

Future<void> _pump(
  WidgetTester tester,
  MensagemThread mensagem, {
  VoidCallback? aoMidiaExpirada,
  AbrirUrlExterna? abrirUrl,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: ChatMessageBubble(
        mensagem: mensagem,
        aoMidiaExpirada: aoMidiaExpirada,
        abrirUrl: abrirUrl,
      ),
    ),
  ),
);

void main() {
  group('P2a — mídia na bolha', () {
    testWidgets('sem mídia: só o texto, nenhum widget de anexo', (
      tester,
    ) async {
      await _pump(tester, _mensagem(null, conteudo: 'Oi'));

      expect(find.text('Oi'), findsOneWidget);
      expect(find.byType(MidiaDaBolha), findsNothing);
    });

    testWidgets('imagem: desenha inline com Image.network', (tester) async {
      await _pump(
        tester,
        _mensagem(_midia(TipoMidia.imagem, mimetype: 'image/jpeg')),
      );

      expect(find.byType(ImagemDaBolha), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('imagem que falha avisa a expiração UMA vez por URL', (
      tester,
    ) async {
      var avisos = 0;
      await _pump(
        tester,
        _mensagem(_midia(TipoMidia.imagem, mimetype: 'image/jpeg')),
        aoMidiaExpirada: () => avisos++,
      );

      // O errorBuilder roda a cada build enquanto o erro durar; chamado
      // várias vezes, o aviso continua sendo um só.
      final imagem = tester.widget<Image>(find.byType(Image));
      final contexto = tester.element(find.byType(Image));
      final substituto = imagem.errorBuilder!(contexto, Exception('x'), null);
      imagem.errorBuilder!(contexto, Exception('x'), null);
      await tester.pump();

      expect(substituto, isA<MidiaIndisponivel>());
      expect(avisos, 1);
    });

    testWidgets('áudio: botão de ouvir e duração, sem criar o player', (
      tester,
    ) async {
      await _pump(
        tester,
        _mensagem(
          _midia(
            TipoMidia.audio,
            mimetype: 'audio/ogg',
            segundos: 75,
            ptt: true,
          ),
        ),
      );

      expect(find.byType(PlayerDeAudio), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byTooltip('Ouvir'), findsOneWidget);
      expect(find.text('1:15'), findsOneWidget);
      // PTT ganha o microfone, como no WhatsApp.
      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('áudio anexado (não PTT) não mostra o microfone', (
      tester,
    ) async {
      await _pump(
        tester,
        _mensagem(_midia(TipoMidia.audio, mimetype: 'audio/mpeg')),
      );

      expect(find.byIcon(Icons.mic), findsNothing);
    });

    testWidgets('vídeo: cartão com duração e tamanho, player só no diálogo', (
      tester,
    ) async {
      await _pump(
        tester,
        _mensagem(
          _midia(
            TipoMidia.video,
            mimetype: 'video/mp4',
            segundos: 9,
            bytes: 2 * 1024 * 1024,
          ),
        ),
      );

      expect(find.text('Vídeo'), findsOneWidget);
      expect(find.text('0:09 · 2,0 MB'), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
    });

    testWidgets('documento: nome e tamanho; clique abre fora do app', (
      tester,
    ) async {
      final abertas = <Uri>[];
      await _pump(
        tester,
        _mensagem(
          _midia(
            TipoMidia.documento,
            mimetype: 'application/pdf',
            nome: 'contrato.pdf',
            bytes: 1536,
          ),
          conteudo: 'contrato.pdf',
        ),
        abrirUrl: (uri) async {
          abertas.add(uri);
          return true;
        },
      );

      // O conteúdo igual ao nome do arquivo não é legenda: aparece uma vez só,
      // no cartão.
      expect(find.text('contrato.pdf'), findsOneWidget);
      expect(find.text('1,5 KB'), findsOneWidget);
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);

      await tester.tap(find.text('contrato.pdf'));
      await tester.pump();

      expect(abertas, [Uri.parse(_url)]);
    });

    testWidgets('documento que não abre avisa com SnackBar', (tester) async {
      await _pump(
        tester,
        _mensagem(_midia(TipoMidia.documento, nome: 'planilha.xlsx')),
        abrirUrl: (_) async => false,
      );

      await tester.tap(find.text('planilha.xlsx'));
      await tester.pump();

      expect(find.text('Não foi possível abrir o documento.'), findsOneWidget);
      expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    });

    testWidgets('documento sem nome cai em "Documento"', (tester) async {
      await _pump(tester, _mensagem(_midia(TipoMidia.documento, nome: '')));

      expect(find.text('Documento'), findsOneWidget);
    });

    testWidgets('legenda diferente do nome do arquivo aparece como texto', (
      tester,
    ) async {
      await _pump(
        tester,
        _mensagem(
          _midia(TipoMidia.documento, nome: 'nota.pdf'),
          conteudo: 'Segue a nota',
        ),
      );

      expect(find.text('Segue a nota'), findsOneWidget);
      expect(find.text('nota.pdf'), findsOneWidget);
    });

    testWidgets('mídia sem legenda (conteúdo vazio) não desenha texto vazio', (
      tester,
    ) async {
      await _pump(
        tester,
        _mensagem(_midia(TipoMidia.audio, mimetype: 'audio/ogg')),
      );

      expect(find.text(''), findsNothing);
    });
  });
}
