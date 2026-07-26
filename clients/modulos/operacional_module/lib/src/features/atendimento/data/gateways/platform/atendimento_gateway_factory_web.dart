import 'package:api_client/api_client.dart' as proto;

import '../../../domain/gateways/atendimento_gateway.dart';
import '../atendimento_remote_gateway.dart';

/// Web: adapter RemoteOnly via gRPC-Web (`AdminServiceClient`). O
/// [tenantIdProvider] é ignorado aqui (o tenant vem do metadata da sessão no
/// servidor); existe só para casar a assinatura com o adapter nativo.
AtendimentoGateway createAtendimentoGateway({
  required proto.AdminServiceClient adminClient,
  required String? Function() tenantIdProvider,
}) => AtendimentoRemoteGateway(client: adminClient);
