import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:login_module/src/features/login/domain/model/session.dart';
import 'package:login_module/src/features/login/domain/parameters/login_parameters.dart';
import 'package:login_module/src/features/login/domain/usecases/login_usecase.dart';
import 'package:login_module/src/features/login/domain/usecases/logout_usecase.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Datasource fake parametrizável: devolve [session]/[data] ou lança [error].
class _FakeSessionDatasource implements Datasource<Session> {
  final Session? session;
  final AppError? error;
  int calls = 0;
  _FakeSessionDatasource({this.session, this.error});

  @override
  Future<Session> call(covariant ParametersReturnResult parameters) async {
    calls++;
    if (error != null) throw error!;
    return session!;
  }
}

class _FakeUnitDatasource implements Datasource<Unit> {
  @override
  Future<Unit> call(covariant ParametersReturnResult parameters) async => unit;
}

Session _session() => Session(
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      tenantId: 't',
      scopes: const ['x'],
      isSuperuser: false,
    );

void main() {
  const params = LoginParameters(email: 'e@e.com', password: 'p');

  test('LoginUsecase: sucesso repassa a Session (passthrough)', () async {
    final ds = _FakeSessionDatasource(session: _session());
    final result = await LoginUsecase(datasource: ds).call(params);

    expect(result, isA<SuccessReturn<Session>>());
    expect((result as SuccessReturn<Session>).result.accessToken, 'a');
    expect(ds.calls, 1);
  });

  test('LoginUsecase: erro do datasource faz short-circuit (process não roda)',
      () async {
    final ds = _FakeSessionDatasource(error: const ErrorAuth());
    final result = await LoginUsecase(datasource: ds).call(params);

    expect(result, isA<ErrorReturn<Session>>());
    // Tipo concreto preservado e mensagem enriquecida com o código de captura.
    final erro = (result as ErrorReturn<Session>).result;
    expect(erro, isA<ErrorAuth>());
    expect(erro.message, contains('Cod. 02-1'));
  });

  test('LogoutUsecase: sucesso resolve em Unit', () async {
    final result =
        await LogoutUsecase(datasource: _FakeUnitDatasource()).call(
      const NoParams(),
    );
    expect(result, isA<SuccessReturn<Unit>>());
  });
}
