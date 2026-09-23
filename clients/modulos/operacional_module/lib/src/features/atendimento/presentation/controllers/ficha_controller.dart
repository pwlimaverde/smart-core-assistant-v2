import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/parameters/definir_valor_campo_parameters.dart';
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
  final DefinirBotDaConversaUsecase _definirBot;
  final DefinirValorCampoUsecase _definirValorCampo;

  /// P5 — o resto da ficha. Opcionais: a conversa embutida em telas que não
  /// registraram o módulo inteiro continua abrindo.
  final RemoverNotaUsecase? _removerNota;
  final AtualizarEtiquetaUsecase? _atualizarEtiqueta;
  final DesativarEtiquetaUsecase? _desativarEtiqueta;

  int _atendimentoId = 0;

  FichaController({
    required GetFichaUsecase carregar,
    required CriarEtiquetaUsecase criarEtiqueta,
    required AlternarEtiquetaUsecase alternar,
    required CriarNotaUsecase criarNota,
    required DefinirBotDaConversaUsecase definirBot,
    required DefinirValorCampoUsecase definirValorCampo,
    RemoverNotaUsecase? removerNota,
    AtualizarEtiquetaUsecase? atualizarEtiqueta,
    DesativarEtiquetaUsecase? desativarEtiqueta,
  }) : _removerNota = removerNota,
       _atualizarEtiqueta = atualizarEtiqueta,
       _desativarEtiqueta = desativarEtiqueta,
       _carregar = carregar,
       _criarEtiqueta = criarEtiqueta,
       _alternar = alternar,
       _criarNota = criarNota,
       _definirBot = definirBot,
       _definirValorCampo = definirValorCampo;

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

  /// P5 — apaga uma nota interna.
  ///
  /// Nota escrita errada ficava para sempre: a v1 deixava excluir, e sem isso
  /// o painel vira um mural que ninguém limpa.
  Future<FichaError?> removerNota(int notaId) async {
    final usecase = _removerNota;
    if (usecase == null) return null;
    final res = await usecase(
      RemoverNotaParameters(notaId: notaId, atendimentoId: _atendimentoId),
    );
    if (res case Failure(:final error)) return error;
    await abrir(_atendimentoId);
    return null;
  }

  /// P5 — renomeia/recolore uma etiqueta do catálogo.
  Future<FichaError?> atualizarEtiqueta({
    required int id,
    required String nome,
    String cor = '',
    String descricao = '',
  }) async {
    final usecase = _atualizarEtiqueta;
    if (usecase == null) return null;
    final res = await usecase(
      AtualizarEtiquetaParameters(
        id: id,
        nome: nome,
        cor: cor,
        descricao: descricao,
      ),
    );
    if (res case Failure(:final error)) return error;
    await abrir(_atendimentoId);
    return null;
  }

  /// P5 — tira a etiqueta do catálogo.
  ///
  /// Ela continua nas conversas em que já estava: desativar é parar de
  /// oferecer, não reescrever o que já aconteceu.
  Future<FichaError?> desativarEtiqueta(int id) async {
    final usecase = _desativarEtiqueta;
    if (usecase == null) return null;
    final res = await usecase(DesativarEtiquetaParameters(id: id));
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

  /// D3 — liga/desliga a IA nesta conversa.
  ///
  /// Recarrega a ficha ao final, como as demais escritas: o servidor é quem diz
  /// em que estado a conversa ficou, e refletir o pedido em vez da resposta
  /// deixaria o interruptor mentindo se a escrita fosse negada.
  Future<FichaError?> definirBot(bool habilitado) async {
    final res = await _definirBot(
      DefinirBotDaConversaParameters(
        atendimentoId: _atendimentoId,
        habilitado: habilitado,
      ),
    );
    if (res case Failure(:final error)) return error;
    await abrir(_atendimentoId);
    return null;
  }

  /// N9 E13 — preenche (ou apaga) um campo do cartão.
  ///
  /// Devolve o erro do **preenchimento**, que tem repertório próprio: um valor
  /// que não serve para o tipo do campo não é a mesma coisa que uma falha ao
  /// carregar a ficha, e a tela precisa dizer qual foi.
  Future<DefinirValorCampoError?> definirValorCampo({
    required int campoId,
    required String valorJson,
  }) async {
    final res = await _definirValorCampo(
      DefinirValorCampoParameters(
        atendimentoId: _atendimentoId,
        campoId: campoId,
        valorJson: valorJson,
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
