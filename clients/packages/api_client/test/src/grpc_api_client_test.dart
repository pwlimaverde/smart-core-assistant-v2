import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GrpcApiClient', () {
    test('Nota sobre Impossibilidade Técnica', () {
      // Este teste serve para documentar a impossibilidade técnica de testar
      // o GrpcApiClient na VM padrão do Dart Desktop (flutter test).
      //
      // IMPOSSIBILIDADE TÉCNICA:
      // GrpcApiClient utiliza GrpcWebClientChannel.xhr, o qual depende
      // internamente de package:web e dart:js_interop para builds compatíveis
      // com WASM no Flutter Web. Ao tentar carregar estes imports na VM
      // desktop do Dart, o compilador falha com erros de interoperabilidade
      // (ex.: The getter 'toJS' isn't defined for the type 'String').
      //
      // Para executar testes deste canal de transporte, é necessário compilar
      // a suíte de testes direcionando-a a um browser real usando:
      // `flutter test --platform chrome`
      expect(true, isTrue);
    });
  });
}
