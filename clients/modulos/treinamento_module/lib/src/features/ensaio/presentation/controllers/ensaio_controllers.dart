import 'package:presentation_module/presentation_module.dart';

import '../../domain/errors/ensaio_errors.dart';
import '../../domain/model/ensaio.dart';
import '../../domain/parameters/ensaio_parameters.dart';
import '../../domain/usecases/ensaio_usecases.dart';

// ignore_for_file: prefer_initializing_formals

/// Ensaio de pergunta: o que a IA responderia, e com base em quê.
final class EnsaioController extends BaseController<Ensaio> {
  final TestarPerguntaUsecase _testar;

  /// A última pergunta enviada. Guardada para a tela poder mostrá-la junto da
  /// resposta — sem isso, quem digitou uma pergunta longa perde a referência
  /// do que perguntou.
  String _ultimaPergunta = '';

  EnsaioController({required TestarPerguntaUsecase testar}) : _testar = testar;

  String get ultimaPergunta => _ultimaPergunta;

  Future<void> testar(String pergunta) {
    _ultimaPergunta = pergunta;
    return execute<EnsaioError>(
      () => _testar(TestarPerguntaParameters(pergunta: pergunta)),
    );
  }
}
