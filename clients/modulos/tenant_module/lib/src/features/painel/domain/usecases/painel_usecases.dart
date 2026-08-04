import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/painel_errors.dart';
import '../model/painel.dart';

final class CarregarPainelUsecase
    extends UsecaseBaseCallData<Painel, Painel, NoParams, PainelError> {
  const CarregarPainelUsecase({required super.repository});

  @override
  ProcessData<Painel, Painel, NoParams, PainelError> get process =>
      (data, _) => Success(data);

  @override
  PainelError onUnexpected(Object e, StackTrace s) {
    developer.log(
      'carregar painel: exceção fora da fronteira',
      name: 'tenant_module.painel.usecase',
      error: e,
      stackTrace: s,
    );
    return const PainelInesperado();
  }
}
