import 'package:api_client/api_client.dart' as proto;
import 'package:mocktail/mocktail.dart';

// `respostaGrpc`/`falhaGrpc` moram no api_client: é lá que o detalhe do
// `ResponseFuture` do gRPC pertence. Reexportados aqui para os testes do módulo
// importarem um arquivo só.
export 'package:api_client/testing.dart' show falhaGrpc, respostaGrpc;

/// Mock do stub gRPC do cadastro — o único ponto trocado nos testes do módulo.
///
/// Os testes montam a cadeia real (`Datasource → Repository → Usecase`) sobre
/// ele, exercitando também a conversão protobuf e o `mapError`.
class MockOnboardingClient extends Mock
    implements proto.OnboardingServiceClient {}

void registrarFallbacksDoCadastro() {
  registerFallbackValue(proto.CheckSlugRequest());
  registerFallbackValue(proto.ListPublicPlansRequest());
  registerFallbackValue(proto.ListPaymentProvidersRequest());
  registerFallbackValue(proto.StartSignupRequest());
  registerFallbackValue(proto.SelectPlanRequest());
  registerFallbackValue(proto.ConfirmPaymentRequest());
  registerFallbackValue(proto.GetSignupStatusRequest());
}

/// Plano padrão dos testes — o Básico que a migration 0027 semeia.
proto.PublicPlan planoBasico() => proto.PublicPlan(
  id: 1,
  name: 'Básico',
  description: 'Plano inicial',
  price: '',
  maxInstances: 3,
  maxDepartments: 3,
  maxFluxos: 5,
);

/// Provedor voucher, como o servidor o descreve.
proto.PaymentProvider provedorVoucher() => proto.PaymentProvider(
  id: 'voucher',
  rotulo: 'Tenho um código de ativação',
  instrucao: 'Informe o código recebido para liberar o acesso.',
  requerCredencial: true,
  rotuloCredencial: 'Código',
  modo: proto.ModoConfirmacao.MODO_CONFIRMACAO_IMEDIATA,
);
