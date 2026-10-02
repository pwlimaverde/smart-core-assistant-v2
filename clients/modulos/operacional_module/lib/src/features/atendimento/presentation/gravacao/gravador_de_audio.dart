import 'dart:developer' as developer;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'apagar_arquivo.dart';

/// Nome com que o áudio gravado sobe. O servidor não usa mais o nome como
/// texto da mensagem (P2b), mas a extensão precisa casar com o contêiner.
const nomeDoAudioGravado = 'audio.m4a';

/// O contêiner do `aacLc` é MP4: `audio/mp4`, e não `audio/aac` nem
/// `audio/m4a`, que o servidor não reconhece pela assinatura.
const mimetypeDoAudioGravado = 'audio/mp4';

/// Abaixo disto é clique acidental no microfone: não vale uma mensagem.
const duracaoMinimaDoAudio = Duration(seconds: 1);

/// O que sobrou de uma gravação ao parar.
sealed class FimDaGravacao {
  const FimDaGravacao();
}

/// Áudio pronto para enviar. O arquivo temporário já foi apagado: os bytes
/// estão em memória.
final class AudioGravado extends FimDaGravacao {
  final List<int> bytes;
  final Duration duracao;

  const AudioGravado({required this.bytes, required this.duracao});
}

/// Menos que [duracaoMinimaDoAudio]: descartado, nada vai ao contato.
final class GravacaoCurta extends FimDaGravacao {
  const GravacaoCurta();
}

/// O gravador não devolveu nada (sem caminho ou arquivo vazio).
final class GravacaoVazia extends FimDaGravacao {
  const GravacaoVazia();
}

/// P2b — o gravador do áudio da conversa, separado da tela.
///
/// Cuida do que a tela não precisa saber: encoder suportado, onde o arquivo
/// fica, a duração mínima e apagar o temporário. O [AudioRecorder] nasce no
/// primeiro uso — abrir uma conversa não deve acordar o microfone nem o canal
/// nativo — e é liberado em [dispose].
///
/// Logs só com encoder, duração e tamanho: o caminho do arquivo tem o nome do
/// usuário do Windows e nunca é registrado.
class GravadorDeAudio {
  GravadorDeAudio({
    AudioRecorder Function()? criarGravador,
    Future<String> Function()? caminhoDoAudio,
    Future<List<int>> Function(String caminho)? lerArquivo,
    Future<void> Function(String caminho)? apagarArquivo,
    DateTime Function()? agora,
  }) : _criarGravador = criarGravador ?? AudioRecorder.new,
       _caminhoDoAudio = caminhoDoAudio ?? _caminhoPadrao,
       _lerArquivo = lerArquivo ?? _lerPadrao,
       _apagarArquivo = apagarArquivo ?? apagarArquivoTemporario,
       _agora = agora ?? DateTime.now;

  /// `aacLc` (.m4a) é o encoder garantido no Windows e o que o servidor
  /// reconhece por assinatura. Nota de voz (opus/ogg) é a etapa 2 da P2b.
  static const config = RecordConfig(encoder: AudioEncoder.aacLc);

  final AudioRecorder Function() _criarGravador;
  final Future<String> Function() _caminhoDoAudio;
  final Future<List<int>> Function(String caminho) _lerArquivo;
  final Future<void> Function(String caminho) _apagarArquivo;
  final DateTime Function() _agora;

  AudioRecorder? _gravador;
  AudioRecorder get _instancia => _gravador ??= _criarGravador();

  DateTime? _inicio;
  String _caminhoAtual = '';

  /// Se há uma gravação em curso.
  bool get gravando => _inicio != null;

  /// Pergunta (e, se preciso, pede) a permissão do microfone.
  Future<bool> temPermissao() => _instancia.hasPermission();

  /// Começa a gravar. Lança se o encoder não existe na plataforma ou se o
  /// `start` falha (microfone ocupado, sem dispositivo) — quem chama avisa a
  /// pessoa; o gravador continua parado e pronto para outra tentativa.
  Future<void> iniciar() async {
    if (gravando) return;
    final gravador = _instancia;
    if (!await gravador.isEncoderSupported(config.encoder)) {
      throw StateError('encoder');
    }
    final caminho = await _caminhoDoAudio();
    await gravador.start(config, path: caminho);
    _caminhoAtual = caminho;
    _inicio = _agora();
    developer.log(
      'gravação iniciada',
      name: 'operacional_module.audio',
      level: 500,
      error: 'encoder=${config.encoder.name}',
    );
  }

  /// Para a gravação e devolve o áudio, ou por que não há o que enviar.
  ///
  /// O arquivo temporário some aqui mesmo, depois de lido: os bytes ficam em
  /// memória até o envio, e um envio que falhe não deixa o áudio no disco.
  Future<FimDaGravacao> parar() async {
    final inicio = _inicio;
    final gravador = _gravador;
    if (inicio == null || gravador == null) return const GravacaoVazia();
    _inicio = null;
    final caminhoPedido = _caminhoAtual;
    _caminhoAtual = '';
    final duracao = _agora().difference(inicio);

    if (duracao < duracaoMinimaDoAudio) {
      // `cancel` para e apaga; o apagar explícito cobre plataforma que não o
      // faça.
      try {
        await gravador.cancel();
      } finally {
        await _apagarSemFalhar(caminhoPedido);
      }
      developer.log(
        'gravação curta descartada',
        name: 'operacional_module.audio',
        level: 500,
        error: 'duracao_ms=${duracao.inMilliseconds}',
      );
      return const GravacaoCurta();
    }

    final caminho = await gravador.stop();
    if (caminho == null || caminho.isEmpty) {
      await _apagarSemFalhar(caminhoPedido);
      return const GravacaoVazia();
    }
    final List<int> bytes;
    try {
      bytes = await _lerArquivo(caminho);
    } finally {
      await _apagarSemFalhar(caminho);
    }
    developer.log(
      'gravação concluída',
      name: 'operacional_module.audio',
      level: 500,
      error:
          'encoder=${config.encoder.name} '
          'duracao_ms=${duracao.inMilliseconds} bytes=${bytes.length}',
    );
    if (bytes.isEmpty) return const GravacaoVazia();
    return AudioGravado(bytes: bytes, duracao: duracao);
  }

  /// Libera o gravador. Uma gravação em curso é descartada (com o arquivo).
  Future<void> dispose() async {
    final gravador = _gravador;
    _gravador = null;
    if (gravador == null) return;
    try {
      if (gravando) {
        _inicio = null;
        await gravador.cancel();
        await _apagarSemFalhar(_caminhoAtual);
      }
      await gravador.dispose();
    } catch (e) {
      developer.log(
        'falha ao liberar o gravador',
        name: 'operacional_module.audio',
        level: 900,
        error: e.runtimeType,
      );
    }
  }

  Future<void> _apagarSemFalhar(String caminho) async {
    if (caminho.isEmpty) return;
    try {
      await _apagarArquivo(caminho);
    } catch (e) {
      // Sobra na pasta temporária, que o sistema limpa; não vale derrubar o
      // envio por isso.
      developer.log(
        'não deu para apagar o áudio temporário',
        name: 'operacional_module.audio',
        level: 900,
        error: e.runtimeType,
      );
    }
  }

  /// Onde o gravador escreve. Na Web não há sistema de arquivos: o `record`
  /// devolve um blob e ignora o caminho.
  static Future<String> _caminhoPadrao() async {
    if (kIsWeb) return '';
    final dir = await getTemporaryDirectory();
    final agora = DateTime.now().millisecondsSinceEpoch;
    return '${dir.path}/ptt_$agora.m4a';
  }

  static Future<List<int>> _lerPadrao(String caminho) =>
      XFile(caminho).readAsBytes();
}
