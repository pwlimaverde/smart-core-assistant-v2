import 'package:api_client/api_client.dart' as proto;

import '../../../domain/datasources/atendimento_data_source.dart';
import '../atendimento_remote_data_source.dart';

/// Web: adapter RemoteOnly via gRPC-Web (`AdminServiceClient`). O
/// [tenantIdProvider] é ignorado aqui (o tenant vem do metadata da sessão no
/// servidor); existe só para casar a assinatura com o adapter nativo.
AtendimentoDataSource createAtendimentoDataSource({
  required proto.AdminServiceClient adminClient,
  required String? Function() tenantIdProvider,
}) =>
    AtendimentoRemoteDataSource(client: adminClient);
