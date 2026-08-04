import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/painel_errors.dart';
import '../../domain/model/painel.dart';
import '../../domain/usecases/painel_usecases.dart';

// ignore_for_file: prefer_initializing_formals

final class PainelController extends BaseController<Painel> {
  final CarregarPainelUsecase _carregar;

  PainelController({required CarregarPainelUsecase carregar})
      : _carregar = carregar;

  Future<void> carregar() => execute<PainelError>(() => _carregar(noParams));
}
