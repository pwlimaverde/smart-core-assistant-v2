import 'dart:convert';

import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/core_settings_errors.dart';
import '../../domain/usecases/core_settings_usecases.dart';
import '../../domain/parameters/core_settings_parameters.dart';
import '../../domain/model/core_setting.dart';

final class CoreSettingsController extends BaseController<List<CoreSetting>> {
  final ListCoreSettingsUsecase _listUsecase;
  final UpsertCoreSettingUsecase _upsertUsecase;
  final DeleteCoreSettingUsecase _deleteUsecase;

  CoreSettingsController({
    required this._listUsecase,
    required this._upsertUsecase,
    required this._deleteUsecase,
  });

  Future<void> fetchSettings() => execute(() => _listUsecase(noParams));

  Future<ReturnSuccessOrError<Unit, CoreSettingsError>> upsertSetting({
    required String key,
    required String value,
    required bool encrypted,
    required String description,
  }) async {
    final res = await _upsertUsecase(
      UpsertCoreSettingParameters(
        key: key,
        value: value,
        encrypted: encrypted,
        description: description,
      ),
    );
    if (res is Success) {
      await fetchSettings();
    }
    return res;
  }

  /// P9 — exporta as configurações como JSON, para levar de um ambiente a
  /// outro. Era o export/import do Django admin da v1.
  ///
  /// **Valor cifrado não sai.** Vai a chave e a descrição, com `valor` vazio:
  /// exportar o segredo em claro para a área de transferência seria vazá-lo, e
  /// o valor cifrado não serve em outro ambiente (a chave de cifra é outra).
  String exportarJson() {
    final itens = switch (state) {
      SuccessState<List<CoreSetting>>(:final data) => data,
      _ => const <CoreSetting>[],
    };
    return const JsonEncoder.withIndent('  ').convert([
      for (final s in itens)
        {
          'key': s.key,
          'value': s.encrypted ? '' : s.value,
          'encrypted': s.encrypted,
          'description': s.description,
        },
    ]);
  }

  /// P9 — importa o JSON de [exportarJson].
  ///
  /// Devolve quantas foram gravadas e quantas puladas. Cifrada sem valor é
  /// pulada, e não gravada vazia: gravar apagaria o segredo que o ambiente de
  /// destino já tem. Recarrega uma vez só, no fim.
  Future<({int gravadas, int puladas, String? erro})> importarJson(
    String json,
  ) async {
    final List<dynamic> lista;
    try {
      final decodificado = jsonDecode(json);
      if (decodificado is! List) {
        return (gravadas: 0, puladas: 0, erro: 'O JSON precisa ser uma lista.');
      }
      lista = decodificado;
    } on FormatException {
      return (gravadas: 0, puladas: 0, erro: 'JSON inválido.');
    }

    var gravadas = 0;
    var puladas = 0;
    for (final item in lista) {
      if (item is! Map) {
        puladas++;
        continue;
      }
      final key = '${item['key'] ?? ''}'.trim();
      final value = '${item['value'] ?? ''}';
      final encrypted = item['encrypted'] == true;
      if (key.isEmpty || (encrypted && value.isEmpty)) {
        puladas++;
        continue;
      }
      final res = await _upsertUsecase(
        UpsertCoreSettingParameters(
          key: key,
          value: value,
          encrypted: encrypted,
          description: '${item['description'] ?? ''}',
        ),
      );
      if (res is Success) {
        gravadas++;
      } else {
        puladas++;
      }
    }
    await fetchSettings();
    return (gravadas: gravadas, puladas: puladas, erro: null);
  }

  Future<ReturnSuccessOrError<Unit, CoreSettingsError>> deleteSetting(
    String key,
  ) async {
    final res = await _deleteUsecase(DeleteCoreSettingParameters(key: key));
    if (res is Success) {
      await fetchSettings();
    }
    return res;
  }
}
