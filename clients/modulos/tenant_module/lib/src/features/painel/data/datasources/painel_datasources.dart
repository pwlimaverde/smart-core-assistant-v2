import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/painel.dart';

final class CarregarPainelDatasource implements Datasource<Painel, NoParams> {
  final proto.AdminServiceClient _client;

  const CarregarPainelDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<Painel> call(NoParams parameters) async {
    final r = await _client.getMyPainel(proto.GetMyPainelRequest());
    return Painel(
      emAndamento: r.emAndamento,
      aguardando: r.aguardando,
      mensagens24h: r.mensagens24h,
      conexoesAtivas: r.conexoesAtivas,
      conexoesTotal: r.conexoesTotal,
      departamentos: r.departamentos,
      treinamentosAtivos: r.treinamentosAtivos,
    );
  }
}
