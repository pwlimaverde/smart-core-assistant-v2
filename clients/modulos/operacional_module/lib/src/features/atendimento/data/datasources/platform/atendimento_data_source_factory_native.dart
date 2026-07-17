import 'package:api_client/api_client.dart' as proto;

import '../../../domain/datasources/atendimento_data_source.dart';
import '../atendimento_local_engine_data_source.dart';

/// Desktop nativo: adapter sobre o motor local Rust via FFI. O [adminClient] é o
/// transporte gRPC do sync da fila offline (mantém o refresh de token no Dart); o
/// [tenantIdProvider] rotula os eventos locais do motor.
AtendimentoDataSource createAtendimentoDataSource({
  required proto.AdminServiceClient adminClient,
  required String? Function() tenantIdProvider,
}) =>
    LocalEngineFfiDataSource(
      tenantIdProvider: tenantIdProvider,
      adminClient: adminClient,
    );
