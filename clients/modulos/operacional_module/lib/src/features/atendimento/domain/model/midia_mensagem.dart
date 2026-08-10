import 'package:meta/meta.dart';

/// O que a conversa sabe fazer com um anexo.
///
/// Categoria, não mimetype: a tela decide entre player de áudio, visualizador de
/// imagem e cartão de documento — a diferença entre `audio/ogg` e `audio/mpeg`
/// não muda nada para ela. O mimetype exato continua disponível em
/// [MidiaMensagem.mimetype] para quem precisar (o player, o download).
enum TipoMidia {
  imagem,
  audio,
  video,
  documento;

  /// Converte o `kind` do servidor. Desconhecido vira [documento]: é o formato
  /// que sempre tem o que mostrar (nome, tamanho, botão de baixar), então um
  /// tipo novo no servidor degrada para "arquivo" em vez de sumir da tela.
  static TipoMidia doServidor(String kind) => switch (kind) {
    'image' => TipoMidia.imagem,
    'audio' => TipoMidia.audio,
    'video' => TipoMidia.video,
    _ => TipoMidia.documento,
  };
}

/// Anexo de uma mensagem da conversa (N9/E2).
///
/// ## Sobre a [urlAssinada]
///
/// É **credencial temporária**, não endereço estável: vale por poucos minutos e
/// dá acesso de leitura ao objeto a quem a tiver. Três consequências práticas
/// para quem mexe nesta classe:
///
/// - **não persistir** (nem em cache de imagem em disco, nem no índice offline);
/// - **não logar** em nenhuma circunstância;
/// - **não guardar em estado de longa duração** — expirada, a imagem para de
///   carregar sem erro claro. O caminho certo é recarregar a thread.
@immutable
final class MidiaMensagem {
  final TipoMidia tipo;
  final String urlAssinada;
  final String mimetype;

  /// Nome original do arquivo. Pode conter PII (nome de cliente, nº de
  /// contrato): exibir, sim; logar, nunca.
  final String nomeArquivo;
  final int tamanhoBytes;

  /// Duração de áudio/vídeo, quando o servidor a conhece.
  final int? segundos;

  /// Áudio gravado na hora (push-to-talk). O WhatsApp mostra diferente de um
  /// arquivo de áudio anexado, e a conversa aqui faz o mesmo.
  final bool ehPtt;

  const MidiaMensagem({
    required this.tipo,
    required this.urlAssinada,
    required this.mimetype,
    required this.nomeArquivo,
    required this.tamanhoBytes,
    this.segundos,
    this.ehPtt = false,
  });

  /// Tamanho legível para a bolha ("2,4 MB"). Vírgula decimal: o app é pt-br.
  String get tamanhoLegivel {
    if (tamanhoBytes <= 0) return '';
    const unidades = ['B', 'KB', 'MB', 'GB'];
    var valor = tamanhoBytes.toDouble();
    var i = 0;
    while (valor >= 1024 && i < unidades.length - 1) {
      valor /= 1024;
      i++;
    }
    final texto = i == 0
        ? valor.toStringAsFixed(0)
        : valor.toStringAsFixed(1).replaceAll('.', ',');
    return '$texto ${unidades[i]}';
  }

  /// Duração no formato `m:ss`, para o player. Vazio quando desconhecida.
  String get duracaoLegivel {
    final s = segundos;
    if (s == null || s <= 0) return '';
    final minutos = s ~/ 60;
    final resto = (s % 60).toString().padLeft(2, '0');
    return '$minutos:$resto';
  }

  /// `toString` sem a URL: a implementação padrão do Dart despejaria a
  /// credencial em qualquer `print` de debug ou relatório de erro.
  @override
  String toString() =>
      'MidiaMensagem(tipo: $tipo, mimetype: $mimetype, bytes: $tamanhoBytes)';
}
