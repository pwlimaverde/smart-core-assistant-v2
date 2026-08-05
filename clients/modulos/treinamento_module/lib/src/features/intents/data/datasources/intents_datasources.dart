import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/intent.dart';
import '../../domain/parameters/intents_parameters.dart';

IntentIa _intent(proto.MyIntent i) => IntentIa(
      id: i.id,
      tag: i.tag,
      grupo: i.grupo,
      descricao: i.descricao,
      exemplo: i.exemplo,
      comportamento: i.comportamento,
      vetorizada: i.vetorizada,
    );

proto.MyIntentDados _dados(DadosIntent d) => proto.MyIntentDados(
      tag: d.tag,
      grupo: d.grupo,
      descricao: d.descricao,
      exemplo: d.exemplo,
      comportamento: d.comportamento,
    );

final class ListarIntentsDatasource
    implements Datasource<List<IntentIa>, NoParams> {
  final proto.AdminServiceClient _client;

  const ListarIntentsDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<List<IntentIa>> call(NoParams parameters) async {
    final resp = await _client.listMyIntents(proto.ListMyIntentsRequest());
    return resp.intents.map(_intent).toList();
  }
}

final class CriarIntentDatasource
    implements Datasource<Unit, CriarIntentParameters> {
  final proto.AdminServiceClient _client;

  const CriarIntentDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<Unit> call(CriarIntentParameters parameters) async {
    await _client.createMyIntent(_dados(parameters.dados));
    return unit;
  }
}

final class AtualizarIntentDatasource
    implements Datasource<Unit, AtualizarIntentParameters> {
  final proto.AdminServiceClient _client;

  const AtualizarIntentDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<Unit> call(AtualizarIntentParameters parameters) async {
    await _client.updateMyIntent(
      proto.UpdateMyIntentRequest(
        id: parameters.id,
        dados: _dados(parameters.dados),
      ),
    );
    return unit;
  }
}

final class RemoverIntentDatasource
    implements Datasource<Unit, IntentIdParameters> {
  final proto.AdminServiceClient _client;

  const RemoverIntentDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<Unit> call(IntentIdParameters parameters) async {
    await _client.removeMyIntent(proto.MyIntentIdRequest(id: parameters.id));
    return unit;
  }
}
