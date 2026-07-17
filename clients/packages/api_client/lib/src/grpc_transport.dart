// ignore_for_file: implementation_imports
import 'api_client.dart';
import 'generated/queries/auth.pbgrpc.dart';
import 'generated/queries/admin.pbgrpc.dart';

/// Contrato neutro do transporte gRPC, independente de plataforma.
///
/// Os stubs [AuthServiceClient]/[AdminServiceClient] são platform-neutros (falam
/// com o `package:grpc/grpc.dart`); só o canal concreto muda: `GrpcWebClientChannel`
/// no browser vs `ClientChannel` (sockets HTTP/2) no desktop. Módulos consumidores
/// dependem desta interface — nunca da implementação concreta — e a seleção real
/// acontece por import condicional na composição do app.
abstract interface class GrpcTransport implements ApiClient {
  /// Stub do `AuthService` (usado pelo `login_module`).
  AuthServiceClient get auth;

  /// Stub do `AdminService` (usado por `admin_module`/`operacional_module`/`tenant_module`).
  AdminServiceClient get admin;
}
