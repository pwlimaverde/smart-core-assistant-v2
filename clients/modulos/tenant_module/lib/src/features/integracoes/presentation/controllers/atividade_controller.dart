import 'package:presentation_module/presentation_module.dart';

import '../../domain/model/atividade.dart';
import '../../domain/parameters/integracoes_parameters.dart';
import '../../domain/usecases/integracoes_usecases.dart';

/// Controller da aba "Atividade" dos aplicativos conectados (B3).
///
/// Guarda os filtros: trocar um deles recarrega a lista com os outros como
/// estavam — a pessoa estreita a busca, não recomeça.
final class AtividadeController extends BaseController<List<Atividade>> {
  final ListarAtividadeUsecase _listar;

  AtividadeController({required this._listar});

  /// Padrão: só agentes. É a pergunta que abre esta aba — "o que os
  /// aplicativos fizeram" — e o que as pessoas fazem no painel já tem as
  /// próprias telas.
  bool soAgentes = true;

  /// Aplicativo escolhido; `null` = todos.
  String? grantId;

  /// Janela em dias, contada a partir de agora.
  int dias = 30;

  Future<void> carregar() => execute(
    () => _listar(
      ListarAtividadeParameters(
        soAgentes: soAgentes,
        grantId: grantId,
        desde: DateTime.now().subtract(Duration(days: dias)),
      ),
    ),
  );

  Future<void> definirSoAgentes(bool valor) {
    soAgentes = valor;
    return carregar();
  }

  Future<void> definirAplicativo(String? id) {
    grantId = id;
    return carregar();
  }

  Future<void> definirPeriodo(int novosDias) {
    dias = novosDias;
    return carregar();
  }
}
