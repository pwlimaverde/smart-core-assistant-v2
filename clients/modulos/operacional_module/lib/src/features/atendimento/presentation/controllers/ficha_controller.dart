import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/atendimento_errors.dart';
import '../../domain/model/ficha.dart';
import '../../domain/parameters/ficha_parameters.dart';
import '../../domain/usecases/atendimento_usecases.dart';

// ignore_for_file: prefer_initializing_formals

/// Ficha do atendimento: etiquetas e anotações.
///
/// Controller separado do chat de propósito: a ficha pode falhar com o
/// histórico carregado, e nesse caso a conversa continua utilizável. Um estado
/// só derrubaria as mensagens junto com o painel.
final class FichaController extends BaseController<FichaAtendimento> {
  final GetFichaUsecase _carregar;
  final CriarEtiquetaUsecase _criarEtiqueta;
  final AlternarEtiquetaUsecase _alternar;
  final CriarNotaUsecase _criarNota;

  int _atendimentoId = 0;

  FichaController({
    required GetFichaUsecase carregar,
    required CriarEtiquetaUsecase criarEtiqueta,
    required AlternarEtiquetaUsecase alternar,
    required CriarNotaUsecase criarNota,
  }) : _carregar = carregar,
       _criarEtiqueta = criarEtiqueta,
       _alternar = alternar,
       _criarNota = criarNota;

  int get atendimentoId => _atendimentoId;

  Future<void> abrir(int atendimentoId) {
    _atendimentoId = atendimentoId;
    return execute<FichaError>(
      () => _carregar(AtendimentoIdParameters(atendimentoId: atendimentoId)),
    );
  }

  Future<FichaError?> criarEtiqueta({
    required String nome,
    required String cor,
  }) async {
    final res = await _criarEtiqueta(
      CriarEtiquetaParameters(nome: nome, cor: cor),
    );
    if (res case Failure(:final error)) return error;
    await abrir(_atendimentoId);
    return null;
  }

  Future<FichaError?> alternar({
    required int etiquetaId,
    required bool aplicar,
  }) async {
    final res = await _alternar(
      AlternarEtiquetaParameters(
        atendimentoId: _atendimentoId,
        etiquetaId: etiquetaId,
        aplicar: aplicar,
      ),
    );
    if (res case Failure(:final error)) return error;
    await abrir(_atendimentoId);
    return null;
  }

  Future<FichaError?> anotar(String texto) async {
    final res = await _criarNota(
      CriarNotaParameters(atendimentoId: _atendimentoId, texto: texto),
    );
    if (res case Failure(:final error)) return error;
    await abrir(_atendimentoId);
    return null;
  }
}
