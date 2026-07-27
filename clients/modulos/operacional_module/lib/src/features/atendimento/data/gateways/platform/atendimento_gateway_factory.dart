// Seleção do adapter do `AtendimentoGateway` por import condicional (mesmo padrão
// do transporte na api_client): Web usa o RemoteOnly (gRPC-Web), o desktop nativo
// usa o motor local via FFI (`local_engine_ffi`, que arrasta `dart:ffi`/lib
// nativa e não compila na Web). `dart.library.js_interop` é verdadeiro só na Web,
// então o desktop cai no adapter nativo.
//
// Ambas as implementações expõem `createAtendimentoGateway({adminClient,
// tenantIdProvider})` devolvendo o mesmo port — nada acima do gateway muda.
export 'atendimento_gateway_factory_native.dart'
    if (dart.library.js_interop) 'atendimento_gateway_factory_web.dart';
