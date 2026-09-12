import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/campos_errors.dart';
import '../model/campo_personalizado.dart';
import '../parameters/campos_parameters.dart';

CamposError _inesperado(String operacao, Object e, StackTrace s) {
  developer.log(
    '$operacao: exceção fora da fronteira',
    name: 'tenant_module.campos.usecase',
    error: e,
    stackTrace: s,
  );
  return const CamposInesperado();
}

final class ListarCamposUsecase
    extends
        UsecaseBaseCallData<
          List<CampoPersonalizado>,
          List<CampoPersonalizado>,
          NoParams,
          CamposError
        > {
  const ListarCamposUsecase({required super.repository});

  @override
  ProcessData<
    List<CampoPersonalizado>,
    List<CampoPersonalizado>,
    NoParams,
    CamposError
  >
  get process => (data, _) {
    // Ordena aqui, e não só no SQL: a tela mistura GLOBAL e de fluxo na mesma
    // lista, e a ordem que interessa a quem lê é a que ela vai desenhar.
    final ordenados = [...data]
      ..sort((a, b) {
        if (a.ordem != b.ordem) return a.ordem.compareTo(b.ordem);
        return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
      });
    return Success(List.unmodifiable(ordenados));
  };

  @override
  CamposError onUnexpected(Object e, StackTrace s) =>
      _inesperado('listar campos', e, s);
}

final class CriarCampoUsecase
    extends
        UsecaseBaseCallData<
          CampoPersonalizado,
          CampoPersonalizado,
          CriarCampoParameters,
          CamposError
        > {
  const CriarCampoUsecase({required super.repository});

  @override
  ProcessData<
    CampoPersonalizado,
    CampoPersonalizado,
    CriarCampoParameters,
    CamposError
  >
  get process =>
      (data, _) => Success(data);

  @override
  CamposError onUnexpected(Object e, StackTrace s) =>
      _inesperado('criar campo', e, s);
}

final class AtualizarCampoUsecase
    extends
        UsecaseBaseCallData<Unit, Unit, AtualizarCampoParameters, CamposError> {
  const AtualizarCampoUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, AtualizarCampoParameters, CamposError> get process =>
      (data, _) => Success(data);

  @override
  CamposError onUnexpected(Object e, StackTrace s) =>
      _inesperado('atualizar campo', e, s);
}

final class DesativarCampoUsecase
    extends UsecaseBaseCallData<Unit, Unit, CampoIdParameters, CamposError> {
  const DesativarCampoUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, CampoIdParameters, CamposError> get process =>
      (data, _) => Success(data);

  @override
  CamposError onUnexpected(Object e, StackTrace s) =>
      _inesperado('desativar campo', e, s);
}
