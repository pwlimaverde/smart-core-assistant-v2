import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/conexoes_errors.dart';
import '../../domain/model/provedor_canal.dart';
import '../../domain/parameters/conexoes_parameters.dart';
import '../../domain/usecases/conexoes_usecases.dart';

// ignore_for_file: prefer_initializing_formals

/// Catálogo de provedores de canal (tela de Integrações) e a conexão por
/// credenciais. O fluxo de QR continua no [ConexoesController], que já conduz
/// o pareamento.
final class IntegracoesController extends BaseController<List<ProvedorCanal>> {
  final ListarProvedoresUsecase _listar;
  final ConectarCanalUsecase _conectar;

  IntegracoesController({
    required ListarProvedoresUsecase listar,
    required ConectarCanalUsecase conectar,
  }) : _listar = listar,
       _conectar = conectar;

  Future<void> carregar() => execute<ConexoesError>(() => _listar(noParams));

  /// Não recarrega o catálogo: ele não muda por causa de uma conexão, e quem
  /// chama está num diálogo que mostra o resultado.
  Future<ReturnSuccessOrError<CanalConectado, ConexoesError>> conectar(
    ConectarCanalParameters parametros,
  ) => _conectar(parametros);
}
