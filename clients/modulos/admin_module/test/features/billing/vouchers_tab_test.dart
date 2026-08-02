// A aba de vouchers e os três diálogos que ela abre.
//
// Testar os diálogos importa mais do que a listagem: é onde estão as decisões
// que o superusuário toma — criar um código, revogá-lo e conferir quem o usou.
import 'package:admin_module/src/features/billing/data/datasources/billing_datasources.dart';
import 'package:admin_module/src/features/billing/data/repositories/billing_repositories.dart';
import 'package:admin_module/src/features/billing/domain/model/plan.dart';
import 'package:admin_module/src/features/billing/domain/model/voucher.dart';
import 'package:admin_module/src/features/billing/domain/usecases/billing_usecases.dart';
import 'package:admin_module/src/features/billing/presentation/controllers/billing_controller.dart';
import 'package:admin_module/src/features/billing/presentation/widgets/vouchers_tab.dart';
import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/admin_grpc_mock.dart';

void main() {
  late MockAdminClient client;

  setUpAll(registrarFallbacksDoAdmin);
  setUp(() => client = MockAdminClient());

  BillingController controller() => BillingController(
    listPlansUsecase: ListPlansUsecase(
      repository: ListPlansRepository(
        datasource: ListPlansDatasource(client: client),
      ),
    ),
    createPlanUsecase: CreatePlanUsecase(
      repository: CreatePlanRepository(
        datasource: CreatePlanDatasource(client: client),
      ),
    ),
    updatePlanUsecase: UpdatePlanUsecase(
      repository: UpdatePlanRepository(
        datasource: UpdatePlanDatasource(client: client),
      ),
    ),
    listSubscriptionsUsecase: ListSubscriptionsUsecase(
      repository: ListSubscriptionsRepository(
        datasource: ListSubscriptionsDatasource(client: client),
      ),
    ),
    registerPaymentUsecase: RegisterPaymentUsecase(
      repository: RegisterPaymentRepository(
        datasource: RegisterPaymentDatasource(client: client),
      ),
    ),
    listPaymentsUsecase: ListPaymentsUsecase(
      repository: ListPaymentsRepository(
        datasource: ListPaymentsDatasource(client: client),
      ),
    ),
    listVouchersUsecase: ListVouchersUsecase(
      repository: ListVouchersRepository(
        datasource: ListVouchersDatasource(client: client),
      ),
    ),
    createVoucherUsecase: CreateVoucherUsecase(
      repository: CreateVoucherRepository(
        datasource: CreateVoucherDatasource(client: client),
      ),
    ),
    revokeVoucherUsecase: RevokeVoucherUsecase(
      repository: RevokeVoucherRepository(
        datasource: RevokeVoucherDatasource(client: client),
      ),
    ),
    listVoucherRedemptionsUsecase: ListVoucherRedemptionsUsecase(
      repository: ListVoucherRedemptionsRepository(
        datasource: ListVoucherRedemptionsDatasource(client: client),
      ),
    ),
  );

  /// As quatro chamadas que `fetchBillingData` dispara ao recarregar depois de
  /// uma escrita. Sem elas, criar/revogar quebra no recarregamento.
  void recargaRespondeVazio() {
    when(
      () => client.listPlans(any()),
    ).thenAnswer((_) => respostaGrpc(proto.ListPlansResponse()));
    when(
      () => client.listSubscriptions(any()),
    ).thenAnswer((_) => respostaGrpc(proto.ListSubscriptionsResponse()));
    when(
      () => client.listPayments(any()),
    ).thenAnswer((_) => respostaGrpc(proto.ListPaymentsResponse()));
    when(
      () => client.listVouchers(any()),
    ).thenAnswer((_) => respostaGrpc(proto.ListVouchersResponse()));
  }

  Voucher voucher({
    String id = 'v-1',
    String codigo = 'DEVTESTE',
    int maxResgates = 0,
    int resgatesUsados = 2,
    DateTime? revogadoEm,
  }) => Voucher(
    id: id,
    codigo: codigo,
    descricao: 'campanha de testes',
    planId: 1,
    planName: 'Básico',
    duracaoDias: 180,
    maxResgates: maxResgates,
    resgatesUsados: resgatesUsados,
    validoDe: DateTime(2026, 1, 1),
    validoAte: null,
    revogadoEm: revogadoEm,
    motivoRevogacao: revogadoEm == null ? '' : 'vazou',
    createdAt: DateTime(2026, 1, 1),
  );

  Plan plano() => Plan(
    id: 1,
    name: 'Básico',
    description: '',
    price: '',
    maxInstances: 3,
    maxDepartments: 3,
    maxFluxos: 5,
    active: true,
    createdAt: DateTime(2026, 1, 1),
  );

  Future<void> montar(
    WidgetTester tester, {
    required List<Voucher> vouchers,
    List<Plan>? planos,
    BillingController? ctrl,
  }) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VouchersTab(
            vouchers: vouchers,
            planos: planos ?? [plano()],
            controller: ctrl ?? controller(),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('lista vazia convida a criar o primeiro', (tester) async {
    await montar(tester, vouchers: const []);
    expect(find.text('Nenhum voucher criado até agora.'), findsOneWidget);
  });

  testWidgets('sem plano cadastrado, não dá para criar voucher', (
    tester,
  ) async {
    // Um voucher concede um plano; sem plano não há o que conceder.
    await montar(tester, vouchers: const [], planos: const []);
    final botao = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Novo voucher'),
    );
    expect(botao.onPressed, isNull);
  });

  testWidgets('voucher revogado não oferece o botão de revogar', (
    tester,
  ) async {
    await montar(
      tester,
      vouchers: [voucher(revogadoEm: DateTime(2026, 6, 1))],
    );
    expect(find.byTooltip('Revogar'), findsNothing);
    expect(find.byTooltip('Ver resgates'), findsOneWidget);
    expect(find.textContaining('revogado: vazou'), findsOneWidget);
  });

  testWidgets('criação envia os valores do formulário', (tester) async {
    recargaRespondeVazio();
    when(() => client.createVoucher(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.CreateVoucherResponse(
          voucher: proto.Voucher(
            id: 'v-2',
            codigo: 'PROMO',
            planId: 1,
            duracaoDias: 30,
            validoDe: ms(DateTime(2026, 1, 1)),
            createdAt: ms(DateTime(2026, 1, 1)),
          ),
        ),
      ),
    );
    await montar(tester, vouchers: const []);

    await tester.tap(find.text('Novo voucher'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Código'), 'PROMO');
    await tester.enterText(
      find.widgetWithText(TextField, 'Duração concedida (dias)'),
      '30',
    );
    await tester.tap(find.text('Criar'));
    await tester.pumpAndSettle();

    final req = verify(
      () => client.createVoucher(captureAny()),
    ).captured.single as proto.CreateVoucherRequest;
    expect(req.codigo, 'PROMO');
    expect(req.duracaoDias, 30);
    expect(req.planId, 1);
    expect(find.text('Voucher criado.'), findsOneWidget);
  });

  testWidgets('revogação avisa que as contas ativas seguem valendo', (
    tester,
  ) async {
    recargaRespondeVazio();
    when(() => client.revokeVoucher(any())).thenAnswer(
      (_) => respostaGrpc(proto.RevokeVoucherResponse(revogado: true)),
    );
    await montar(tester, vouchers: [voucher()]);

    await tester.tap(find.byTooltip('Revogar'));
    await tester.pumpAndSettle();

    // O texto do diálogo responde à dúvida de quem está prestes a clicar.
    expect(
      find.textContaining('continuam ativas até o fim do período'),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Motivo (fica no registro)'),
      'código vazou',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Revogar'));
    await tester.pumpAndSettle();

    final req = verify(
      () => client.revokeVoucher(captureAny()),
    ).captured.single as proto.RevokeVoucherRequest;
    expect(req.voucherId, 'v-1');
    expect(req.motivo, 'código vazou');
    expect(find.text('Voucher revogado.'), findsOneWidget);
  });

  testWidgets('revogar de novo avisa que nada mudou', (tester) async {
    // `revogado: false` não é erro — mas o superusuário precisa saber que o
    // clique dele não teve efeito.
    recargaRespondeVazio();
    when(() => client.revokeVoucher(any())).thenAnswer(
      (_) => respostaGrpc(proto.RevokeVoucherResponse(revogado: false)),
    );
    await montar(tester, vouchers: [voucher()]);

    await tester.tap(find.byTooltip('Revogar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Revogar'));
    await tester.pumpAndSettle();

    expect(find.text('Este voucher já estava revogado.'), findsOneWidget);
  });

  testWidgets('histórico mostra quem resgatou', (tester) async {
    when(() => client.listVoucherRedemptions(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.ListVoucherRedemptionsResponse(
          resgates: [
            proto.VoucherRedemption(
              id: 'r-1',
              voucherId: 'v-1',
              tenantId: 'tenant-abc',
              planId: 1,
              periodoInicio: ms(DateTime(2026, 7, 1)),
              periodoFim: ms(DateTime(2026, 12, 28)),
              ip: '203.0.113.7',
              redeemedAt: ms(DateTime(2026, 7, 1)),
            ),
          ],
        ),
      ),
    );
    await montar(tester, vouchers: [voucher()]);

    await tester.tap(find.byTooltip('Ver resgates'));
    await tester.pumpAndSettle();

    expect(find.text('tenant-abc'), findsOneWidget);
    expect(find.textContaining('28/12/2026'), findsOneWidget);
    expect(find.textContaining('203.0.113.7'), findsOneWidget);
  });

  testWidgets('voucher sem resgates diz isso', (tester) async {
    when(() => client.listVoucherRedemptions(any())).thenAnswer(
      (_) => respostaGrpc(proto.ListVoucherRedemptionsResponse()),
    );
    await montar(tester, vouchers: [voucher()]);

    await tester.tap(find.byTooltip('Ver resgates'));
    await tester.pumpAndSettle();

    expect(find.text('Este voucher ainda não foi usado.'), findsOneWidget);
  });

  testWidgets('falha ao buscar o histórico aparece como aviso', (tester) async {
    when(() => client.listVoucherRedemptions(any())).thenAnswer(
      (_) => falhaGrpc<proto.ListVoucherRedemptionsResponse>(
        proto.GrpcError.unavailable(),
      ),
    );
    await montar(tester, vouchers: [voucher()]);

    await tester.tap(find.byTooltip('Ver resgates'));
    await tester.pumpAndSettle();

    expect(find.textContaining('indisponível'), findsOneWidget);
  });
}
