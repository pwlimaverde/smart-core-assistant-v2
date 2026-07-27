import 'package:api_client/api_client.dart' as proto;

import '../../../domain/gateways/atendimento_gateway.dart';
import '../local_engine_gateway.dart';

/// Desktop nativo: adapter sobre o motor local Rust via FFI. O [adminClient] é o
/// transporte gRPC do sync da fila offline (mantém o refresh de token no Dart); o
/// [tenantIdProvider] rotula os eventos locais do motor.
AtendimentoGateway createAtendimentoGateway({
  required proto.AdminServiceClient adminClient,
  required String? Function() tenantIdProvider,
}) => LocalEngineGateway(
  tenantIdProvider: tenantIdProvider,
  adminClient: adminClient,
);
