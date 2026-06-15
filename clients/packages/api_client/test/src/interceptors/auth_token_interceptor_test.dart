import 'package:api_client/src/interceptors/auth_token_interceptor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:mocktail/mocktail.dart';

class MockClientMethod<Q, R> extends Mock implements ClientMethod<Q, R> {}

class MockClientUnaryInvoker<Q, R> extends Mock {
  ResponseFuture<R> call(ClientMethod<Q, R> method, Q request, CallOptions options);
}

class FakeResponseFuture<R> extends Mock implements ResponseFuture<R> {}

class MockInvokerStreaming extends Mock {
  ResponseStream<R> call<Q, R>(
    ClientMethod<Q, R> method,
    Stream<Q> requests,
    CallOptions options,
  );
}

class FakeResponseStream<R> extends Mock implements ResponseStream<R> {}

void main() {
  setUpAll(() {
    registerFallbackValue(CallOptions());
    registerFallbackValue(MockClientMethod<String, String>());
    registerFallbackValue(Stream<String>.empty());
  });

  group('AuthTokenInterceptor', () {
    late MockClientMethod<String, String> mockMethod;
    late MockClientUnaryInvoker<String, String> mockInvoker;
    late FakeResponseFuture<String> fakeResponse;

    setUp(() {
      mockMethod = MockClientMethod<String, String>();
      mockInvoker = MockClientUnaryInvoker<String, String>();
      fakeResponse = FakeResponseFuture<String>();

      when(() => mockInvoker.call(any(), any(), any())).thenAnswer((_) => fakeResponse);
    });

    test('injeta access token quando presente e não vazio', () async {
      final interceptor = AuthTokenInterceptor(() async => 'meu_token_123');

      interceptor.interceptUnary<String, String>(
        mockMethod,
        'requisicao',
        CallOptions(),
        mockInvoker.call,
      );

      final captured = verify(
        () => mockInvoker.call(mockMethod, 'requisicao', captureAny()),
      ).captured.single as CallOptions;

      final metadata = <String, String>{};
      for (final provider in captured.metadataProviders) {
        await provider(metadata, 'some_uri');
      }

      expect(metadata['authorization'], 'Bearer meu_token_123');
    });

    test('não injeta access token quando nulo', () async {
      final interceptor = AuthTokenInterceptor(() async => null);

      interceptor.interceptUnary<String, String>(
        mockMethod,
        'requisicao',
        CallOptions(),
        mockInvoker.call,
      );

      final captured = verify(
        () => mockInvoker.call(mockMethod, 'requisicao', captureAny()),
      ).captured.single as CallOptions;

      final metadata = <String, String>{};
      for (final provider in captured.metadataProviders) {
        await provider(metadata, 'some_uri');
      }

      expect(metadata.containsKey('authorization'), isFalse);
    });

    test('não injeta access token quando vazio', () async {
      final interceptor = AuthTokenInterceptor(() async => '');

      interceptor.interceptUnary<String, String>(
        mockMethod,
        'requisicao',
        CallOptions(),
        mockInvoker.call,
      );

      final captured = verify(
        () => mockInvoker.call(mockMethod, 'requisicao', captureAny()),
      ).captured.single as CallOptions;

      final metadata = <String, String>{};
      for (final provider in captured.metadataProviders) {
        await provider(metadata, 'some_uri');
      }

      expect(metadata.containsKey('authorization'), isFalse);
    });

    test('interceptStreaming apenas repassa a chamada sem alterações', () {
      final interceptor = AuthTokenInterceptor(() async => 'token');
      final mockRequests = Stream<String>.value('req');
      final mockInvokerStreaming = MockInvokerStreaming();

      when(() => mockInvokerStreaming.call<String, String>(any(), any(), any()))
          .thenAnswer((_) => FakeResponseStream<String>());

      interceptor.interceptStreaming<String, String>(
        mockMethod,
        mockRequests,
        CallOptions(),
        mockInvokerStreaming.call,
      );

      verify(() => mockInvokerStreaming.call(mockMethod, mockRequests, any())).called(1);
    });
  });
}
