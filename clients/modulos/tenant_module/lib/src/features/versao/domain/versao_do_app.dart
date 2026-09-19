import 'package:domain_models/domain_models.dart';
import 'package:meta/meta.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// P11 — o número de build carimbado neste binário pelo `build-windows.ps1`.
///
/// 0 quando o app não veio do script (rodando pelo `flutter run`, por
/// exemplo): sem saber a própria versão, ele não tem como dizer que está velho.
const int buildLocal = int.fromEnvironment('SMARTCORE_APP_BUILD');

/// P11 — a última versão publicada.
@immutable
final class VersaoPublicada {
  final int build;
  final String urlDownload;
  final String notas;

  const VersaoPublicada({
    required this.build,
    required this.urlDownload,
    required this.notas,
  });

  /// Só avisa com os três dados certos: build local conhecido, build publicado
  /// maior, e um lugar para baixar — faixa sem botão seria só incômodo.
  bool maisNovaQue(int local) =>
      local > 0 && build > local && urlDownload.isNotEmpty;
}

/// A consulta de versão falhou. Nunca vira tela de erro: o aviso é acessório.
final class VersaoIndisponivel extends AppError {
  const VersaoIndisponivel() : super('Não foi possível consultar a versão.');
}

final class ConsultarVersaoParameters extends Parameters {
  final String plataforma;

  const ConsultarVersaoParameters({this.plataforma = 'windows'});
}

final class ConsultarVersaoUsecase
    extends
        UsecaseBaseCallData<
          VersaoPublicada,
          VersaoPublicada,
          ConsultarVersaoParameters,
          VersaoIndisponivel
        > {
  const ConsultarVersaoUsecase({required super.repository});

  @override
  ProcessData<
    VersaoPublicada,
    VersaoPublicada,
    ConsultarVersaoParameters,
    VersaoIndisponivel
  >
  get process =>
      (data, _) => Success(data);

  @override
  VersaoIndisponivel onUnexpected(Object e, StackTrace s) =>
      const VersaoIndisponivel();
}
