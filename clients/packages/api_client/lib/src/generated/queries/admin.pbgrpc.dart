// This is a generated file - do not edit.
//
// Generated from queries/admin.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;

import 'admin.pb.dart' as $0;

export 'admin.pb.dart';

/// --- Serviço Admin ---
@$pb.GrpcServiceName('smartcore.contracts.queries.AdminService')
class AdminServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  AdminServiceClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.ListCoreSettingsResponse> listCoreSettings(
    $0.ListCoreSettingsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listCoreSettings, request, options: options);
  }

  $grpc.ResponseFuture<$0.UpsertCoreSettingResponse> upsertCoreSetting(
    $0.UpsertCoreSettingRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$upsertCoreSetting, request, options: options);
  }

  $grpc.ResponseFuture<$0.DeleteCoreSettingResponse> deleteCoreSetting(
    $0.DeleteCoreSettingRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$deleteCoreSetting, request, options: options);
  }

  $grpc.ResponseFuture<$0.GetTenantConfigResponse> getTenantConfig(
    $0.GetTenantConfigRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getTenantConfig, request, options: options);
  }

  $grpc.ResponseFuture<$0.UpdateTenantConfigResponse> updateTenantConfig(
    $0.UpdateTenantConfigRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$updateTenantConfig, request, options: options);
  }

  /// Fase 2: Tenants
  $grpc.ResponseFuture<$0.AdminListUsersResponse> adminListUsers(
    $0.AdminListUsersRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$adminListUsers, request, options: options);
  }

  $grpc.ResponseFuture<$0.AdminSetUserActiveResponse> adminSetUserActive(
    $0.AdminSetUserActiveRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$adminSetUserActive, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListTenantsResponse> listTenants(
    $0.ListTenantsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listTenants, request, options: options);
  }

  $grpc.ResponseFuture<$0.GetTenantResponse> getTenant(
    $0.GetTenantRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getTenant, request, options: options);
  }

  $grpc.ResponseFuture<$0.CreateTenantResponse> createTenant(
    $0.CreateTenantRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createTenant, request, options: options);
  }

  $grpc.ResponseFuture<$0.UpdateTenantResponse> updateTenant(
    $0.UpdateTenantRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$updateTenant, request, options: options);
  }

  $grpc.ResponseFuture<$0.SetTenantActiveResponse> setTenantActive(
    $0.SetTenantActiveRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setTenantActive, request, options: options);
  }

  $grpc.ResponseFuture<$0.GenerateAccessCodeResponse> generateAccessCode(
    $0.GenerateAccessCodeRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$generateAccessCode, request, options: options);
  }

  /// Fase 2: Billing
  $grpc.ResponseFuture<$0.ListPlansResponse> listPlans(
    $0.ListPlansRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listPlans, request, options: options);
  }

  $grpc.ResponseFuture<$0.CreatePlanResponse> createPlan(
    $0.CreatePlanRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createPlan, request, options: options);
  }

  $grpc.ResponseFuture<$0.UpdatePlanResponse> updatePlan(
    $0.UpdatePlanRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$updatePlan, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListSubscriptionsResponse> listSubscriptions(
    $0.ListSubscriptionsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listSubscriptions, request, options: options);
  }

  $grpc.ResponseFuture<$0.RegisterPaymentResponse> registerPayment(
    $0.RegisterPaymentRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$registerPayment, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListPaymentsResponse> listPayments(
    $0.ListPaymentsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listPayments, request, options: options);
  }

  /// Vouchers de ativação
  $grpc.ResponseFuture<$0.ListVouchersResponse> listVouchers(
    $0.ListVouchersRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listVouchers, request, options: options);
  }

  $grpc.ResponseFuture<$0.CreateVoucherResponse> createVoucher(
    $0.CreateVoucherRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createVoucher, request, options: options);
  }

  $grpc.ResponseFuture<$0.RevokeVoucherResponse> revokeVoucher(
    $0.RevokeVoucherRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$revokeVoucher, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListVoucherRedemptionsResponse>
      listVoucherRedemptions(
    $0.ListVoucherRedemptionsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listVoucherRedemptions, request,
        options: options);
  }

  /// Fase 3: Evolution Connection
  $grpc.ResponseFuture<$0.TestEvolutionConnectionResponse>
      testEvolutionConnection(
    $0.TestEvolutionConnectionRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$testEvolutionConnection, request,
        options: options);
  }

  /// P9 — o `test-connection` da v1 para o provedor de IA: um embedding de
  /// ensaio com a configuração do tenant. Hoje só se descobria que a chave do
  /// provedor tinha expirado quando o bot parava de responder.
  $grpc.ResponseFuture<$0.TestarProvedorIaResponse> testarProvedorIa(
    $0.TestarProvedorIaRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$testarProvedorIa, request, options: options);
  }

  /// Fase 4: Feature Flags
  $grpc.ResponseFuture<$0.ListFeatureFlagsResponse> listFeatureFlags(
    $0.ListFeatureFlagsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listFeatureFlags, request, options: options);
  }

  $grpc.ResponseFuture<$0.SetFeatureFlagResponse> setFeatureFlag(
    $0.SetFeatureFlagRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setFeatureFlag, request, options: options);
  }

  $grpc.ResponseFuture<$0.SetFeatureFlagOverrideResponse>
      setFeatureFlagOverride(
    $0.SetFeatureFlagOverrideRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setFeatureFlagOverride, request,
        options: options);
  }

  /// Fase 5: Auditoria & Saúde
  $grpc.ResponseFuture<$0.QueryAuditLogResponse> queryAuditLog(
    $0.QueryAuditLogRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$queryAuditLog, request, options: options);
  }

  $grpc.ResponseFuture<$0.GetServiceHealthResponse> getServiceHealth(
    $0.GetServiceHealthRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getServiceHealth, request, options: options);
  }

  $grpc.ResponseFuture<$0.GetDashboardSummaryResponse> getDashboardSummary(
    $0.GetDashboardSummaryRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getDashboardSummary, request, options: options);
  }

  $grpc.ResponseStream<$0.ExportTenantsCsvResponse> exportTenantsCsv(
    $0.ExportTenantsCsvRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$exportTenantsCsv, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// Realtime
  $grpc.ResponseStream<$0.AtendimentoEvent> streamAtendimentos(
    $0.StreamAtendimentosRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$streamAtendimentos, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// Fase 6: Operacional (fila/Kanban/chat — WS-6). RBAC fino por fluxo (flow_permissions)
  /// já é aplicado no data_postgres (WS-5a); estas rotas exigem só autenticação, não superuser.
  $grpc.ResponseFuture<$0.ListAtendimentosResponse> listAtendimentos(
    $0.ListAtendimentosRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listAtendimentos, request, options: options);
  }

  $grpc.ResponseFuture<$0.GetThreadResponse> getThread(
    $0.GetThreadRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getThread, request, options: options);
  }

  $grpc.ResponseFuture<$0.IniciarAtendimentoManualResponse>
      iniciarAtendimentoManual(
    $0.IniciarAtendimentoManualRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$iniciarAtendimentoManual, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.MoveAtendimentoEtapaResponse> moveAtendimentoEtapa(
    $0.MoveAtendimentoEtapaRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$moveAtendimentoEtapa, request, options: options);
  }

  $grpc.ResponseFuture<$0.SetAtendimentoStatusResponse> setAtendimentoStatus(
    $0.SetAtendimentoStatusRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setAtendimentoStatus, request, options: options);
  }

  /// Ficha do atendimento: etiquetas e anotacoes internas. As tabelas
  /// existiam desde o comeco e nenhum app as alcancava.
  $grpc.ResponseFuture<$0.DetalheAtendimentoResponse> getDetalheAtendimento(
    $0.AtendimentoIdRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getDetalheAtendimento, request, options: options);
  }

  $grpc.ResponseFuture<$0.EtiquetaResponse> createEtiqueta(
    $0.CreateEtiquetaRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createEtiqueta, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> alternarEtiqueta(
    $0.AlternarEtiquetaRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$alternarEtiqueta, request, options: options);
  }

  $grpc.ResponseFuture<$0.NotaResponse> createNota(
    $0.CreateNotaRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createNota, request, options: options);
  }

  $grpc.ResponseFuture<$0.SendOutboundMessageResponse> sendOutboundMessage(
    $0.SendOutboundMessageRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$sendOutboundMessage, request, options: options);
  }

  /// N9a — mídia na conversa. Upload em duas etapas (presign + confirmação) para
  /// o binário não passar pelo envelope.
  $grpc.ResponseFuture<$0.SolicitarUploadMidiaResponse> solicitarUploadMidia(
    $0.SolicitarUploadMidiaRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$solicitarUploadMidia, request, options: options);
  }

  $grpc.ResponseFuture<$0.EnviarMidiaAtendimentoResponse>
      enviarMidiaAtendimento(
    $0.EnviarMidiaAtendimentoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$enviarMidiaAtendimento, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.ListarMidiasAtendimentoResponse>
      listarMidiasAtendimento(
    $0.ListarMidiasAtendimentoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listarMidiasAtendimento, request,
        options: options);
  }

  /// P3 — presenca do atendente na conversa (efemera).
  $grpc.ResponseFuture<$0.EnviarPresencaResponse> enviarPresenca(
    $0.EnviarPresencaRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$enviarPresenca, request, options: options);
  }

  /// P5 — a ficha completa.
  $grpc.ResponseFuture<$0.ListarTimelineResponse> listarTimelineAtendimento(
    $0.ListarTimelineRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listarTimelineAtendimento, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.ListarAtendimentosDoContatoResponse>
      listarAtendimentosDoContato(
    $0.ListarAtendimentosDoContatoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listarAtendimentosDoContato, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> removerNota(
    $0.RemoverNotaRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$removerNota, request, options: options);
  }

  $grpc.ResponseFuture<$0.EtiquetaResponse> updateEtiqueta(
    $0.UpdateEtiquetaRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$updateEtiqueta, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> desativarEtiqueta(
    $0.DesativarEtiquetaRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$desativarEtiqueta, request, options: options);
  }

  /// P4 — operacao do quadro pelo supervisor.
  $grpc.ResponseFuture<$0.AtribuirAtendimentoResponse> atribuirAtendimento(
    $0.AtribuirAtendimentoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$atribuirAtendimento, request, options: options);
  }

  $grpc.ResponseFuture<$0.DefinirPrioridadeResponse> definirPrioridade(
    $0.DefinirPrioridadeRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$definirPrioridade, request, options: options);
  }

  $grpc.ResponseFuture<$0.TransferirParaFluxoResponse> transferirParaFluxo(
    $0.TransferirParaFluxoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$transferirParaFluxo, request, options: options);
  }

  $grpc.ResponseFuture<$0.ExportarQuadroResponse> exportarQuadro(
    $0.ExportarQuadroRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$exportarQuadro, request, options: options);
  }

  /// Fase N3: Painel do Tenant. Exigem só autenticação (não superuser); o RBAC fino
  /// `tenant:admin` é aplicado no data_postgres. AcceptInvite é rota pública (sem sessão).
  $grpc.ResponseFuture<$0.CreateInviteResponse> createInvite(
    $0.CreateInviteRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createInvite, request, options: options);
  }

  $grpc.ResponseFuture<$0.AcceptInviteResponse> acceptInvite(
    $0.AcceptInviteRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$acceptInvite, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListInvitesResponse> listInvites(
    $0.ListInvitesRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listInvites, request, options: options);
  }

  $grpc.ResponseFuture<$0.RevokeInviteResponse> revokeInvite(
    $0.RevokeInviteRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$revokeInvite, request, options: options);
  }

  $grpc.ResponseFuture<$0.ReenviarConviteResponse> reenviarConvite(
    $0.ReenviarConviteRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$reenviarConvite, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListTenantUsersResponse> listTenantUsers(
    $0.ListTenantUsersRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listTenantUsers, request, options: options);
  }

  $grpc.ResponseFuture<$0.UpdateTenantUserResponse> updateTenantUser(
    $0.UpdateTenantUserRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$updateTenantUser, request, options: options);
  }

  $grpc.ResponseFuture<$0.GetTenantConfigResponse> getMyTenantConfig(
    $0.GetMyTenantConfigRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getMyTenantConfig, request, options: options);
  }

  $grpc.ResponseFuture<$0.UpdateTenantConfigResponse> updateMyTenantConfig(
    $0.UpdateMyTenantConfigRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$updateMyTenantConfig, request, options: options);
  }

  /// Fase N13: aplicativos de IA conectados por OAuth 2.1 (servidor MCP).
  /// Cada usuário enxerga e revoga APENAS os próprios consentimentos — nem um
  /// `tenant:admin` vê o do colega. Por isso não há variante administrativa.
  $grpc.ResponseFuture<$0.ListMcpGrantsResponse> listMcpGrants(
    $0.ListMcpGrantsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listMcpGrants, request, options: options);
  }

  $grpc.ResponseFuture<$0.RevokeMcpGrantResponse> revokeMcpGrant(
    $0.RevokeMcpGrantRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$revokeMcpGrant, request, options: options);
  }

  $grpc.ResponseFuture<$0.AjustarEscoposMcpGrantResponse>
      ajustarEscoposMcpGrant(
    $0.AjustarEscoposMcpGrantRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$ajustarEscoposMcpGrant, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.ListMyAuditLogResponse> listMyAuditLog(
    $0.ListMyAuditLogRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listMyAuditLog, request, options: options);
  }

  /// Configuração inicial guiada (passos 5 a 8)
  $grpc.ResponseFuture<$0.CreateMyWhatsappInstanceResponse>
      createMyWhatsappInstance(
    $0.CreateMyWhatsappInstanceRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createMyWhatsappInstance, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.GetMyWhatsappInstanceStatusResponse>
      getMyWhatsappInstanceStatus(
    $0.GetMyWhatsappInstanceStatusRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getMyWhatsappInstanceStatus, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.CreateMyDepartamentoResponse> createMyDepartamento(
    $0.CreateMyDepartamentoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createMyDepartamento, request, options: options);
  }

  $grpc.ResponseFuture<$0.SetMyBotPersonaResponse> setMyBotPersona(
    $0.SetMyBotPersonaRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setMyBotPersona, request, options: options);
  }

  $grpc.ResponseFuture<$0.SetOnboardingProgressResponse> setOnboardingProgress(
    $0.SetOnboardingProgressRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setOnboardingProgress, request, options: options);
  }

  $grpc.ResponseFuture<$0.GetMyOnboardingProgressResponse>
      getMyOnboardingProgress(
    $0.GetMyOnboardingProgressRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getMyOnboardingProgress, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.QuitarMinhaAssinaturaResponse> quitarMinhaAssinatura(
    $0.QuitarMinhaAssinaturaRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$quitarMinhaAssinatura, request, options: options);
  }

  /// Treinamento da IA (o tenant treina o próprio assistente)
  $grpc.ResponseFuture<$0.MyTreinamentoResponse> createMyTreinamento(
    $0.CreateMyTreinamentoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createMyTreinamento, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListMyTreinamentosResponse> listMyTreinamentos(
    $0.ListMyTreinamentosRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listMyTreinamentos, request, options: options);
  }

  /// Curadoria de intencoes: o que a IA deve FAZER quando a pergunta se parecer
  /// com um exemplo. Complementa o material treinado, que diz o que ela SABE.
  $grpc.ResponseFuture<$0.ListMyIntentsResponse> listMyIntents(
    $0.ListMyIntentsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listMyIntents, request, options: options);
  }

  $grpc.ResponseFuture<$0.MyIntentResponse> createMyIntent(
    $0.MyIntentDados request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createMyIntent, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> updateMyIntent(
    $0.UpdateMyIntentRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$updateMyIntent, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> removeMyIntent(
    $0.MyIntentIdRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$removeMyIntent, request, options: options);
  }

  /// Ensaio: a pergunta percorre o MESMO caminho de uma mensagem real (embed ->
  /// RAG -> LLM), sem gravar atendimento nenhum. Validar o treinamento pelo
  /// WhatsApp de verdade obrigaria a usar um numero real e sujar o historico.
  $grpc.ResponseFuture<$0.TestarPerguntaResponse> testarPergunta(
    $0.TestarPerguntaRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$testarPergunta, request, options: options);
  }

  $grpc.ResponseFuture<$0.SolicitarUploadTreinamentoResponse>
      solicitarUploadTreinamento(
    $0.SolicitarUploadTreinamentoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$solicitarUploadTreinamento, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.MyTreinamentoResponse> createMyTreinamentoComArquivo(
    $0.CreateMyTreinamentoComArquivoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createMyTreinamentoComArquivo, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.RegistrarFeedbackTesteResponse>
      registrarFeedbackTeste(
    $0.RegistrarFeedbackTesteRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$registrarFeedbackTeste, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.MyTreinamentoResponse> getMyTreinamento(
    $0.GetMyTreinamentoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getMyTreinamento, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> finalizarMyTreinamento(
    $0.FinalizarMyTreinamentoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$finalizarMyTreinamento, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> removerMyTreinamento(
    $0.RemoverMyTreinamentoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$removerMyTreinamento, request, options: options);
  }

  /// Gestão das conexões de WhatsApp DEPOIS de conectadas.
  ///
  /// O onboarding cria a primeira; sem estas, uma conexão que cai deixa o tenant
  /// sem saída — não há como ver o estado, reconectar nem trocar de aparelho.
  $grpc.ResponseFuture<$0.ListMyWhatsappInstancesResponse>
      listMyWhatsappInstances(
    $0.ListMyWhatsappInstancesRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listMyWhatsappInstances, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.DefinirRespostaBotInstanciaResponse>
      definirRespostaBotInstancia(
    $0.DefinirRespostaBotInstanciaRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$definirRespostaBotInstancia, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.DefinirBotDaConversaResponse> definirBotDaConversa(
    $0.DefinirBotDaConversaRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$definirBotDaConversa, request, options: options);
  }

  /// B6 (N9/E4): abrir a conversa e chegar ao fim dela marca o que o contato mandou.
  $grpc.ResponseFuture<$0.MarcarAtendimentoLidoResponse> marcarAtendimentoLido(
    $0.MarcarAtendimentoLidoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$marcarAtendimentoLido, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> reconnectMyWhatsappInstance(
    $0.MyWhatsappInstanceIdRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$reconnectMyWhatsappInstance, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> deleteMyWhatsappInstance(
    $0.MyWhatsappInstanceIdRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$deleteMyWhatsappInstance, request,
        options: options);
  }

  /// P7 — encerra a SESSÃO sem apagar a conexão: o histórico e o cadastro ficam,
  /// e o mesmo registro volta com um QR novo. Remover era a única saída, e ela
  /// custava o cadastro inteiro para trocar de aparelho.
  $grpc.ResponseFuture<$0.SimpleOkResponse> desconectarMyWhatsappInstance(
    $0.MyWhatsappInstanceIdRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$desconectarMyWhatsappInstance, request,
        options: options);
  }

  /// P11 — a última versão publicada do app. Até aqui o zip era trocado à mão,
  /// e ninguém sabia que estava numa versão velha até um bug já corrigido
  /// aparecer de novo.
  $grpc.ResponseFuture<$0.GetVersaoDoAppResponse> getVersaoDoApp(
    $0.GetVersaoDoAppRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getVersaoDoApp, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> definirDepartamentoDaConexao(
    $0.DefinirDepartamentoDaConexaoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$definirDepartamentoDaConexao, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.DetalheDaConexaoResponse> detalheDaConexao(
    $0.DetalheDaConexaoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$detalheDaConexao, request, options: options);
  }

  /// P9 — mensagens que o atendente mandou e que não tinham para onde ir. O
  /// reprocessamento existia desde a N7.2 e não era alcançável de tela nenhuma:
  /// a mensagem ficava parada para sempre sem ninguém saber.
  $grpc.ResponseFuture<$0.ListMyMensagensNaoEntreguesResponse>
      listMyMensagensNaoEntregues(
    $0.ListMyMensagensNaoEntreguesRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listMyMensagensNaoEntregues, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.ReenviarMensagemNaoEntregueResponse>
      reenviarMensagemNaoEntregue(
    $0.ReenviarMensagemNaoEntregueRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$reenviarMensagemNaoEntregue, request,
        options: options);
  }

  /// P7 — os números que o sistema ignora (a "whitelist" da v1).
  $grpc.ResponseFuture<$0.ListMyNumerosIgnoradosResponse>
      listMyNumerosIgnorados(
    $0.ListMyNumerosIgnoradosRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listMyNumerosIgnorados, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.MyNumeroIgnoradoResponse> criarNumeroIgnorado(
    $0.CriarNumeroIgnoradoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$criarNumeroIgnorado, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> atualizarNumeroIgnorado(
    $0.AtualizarNumeroIgnoradoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$atualizarNumeroIgnorado, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> removerNumeroIgnorado(
    $0.NumeroIgnoradoIdRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$removerNumeroIgnorado, request, options: options);
  }

  /// Departamentos e atendentes — a estrutura para onde a fila manda conversa.
  $grpc.ResponseFuture<$0.ListMyDepartamentosResponse> listMyDepartamentos(
    $0.ListMyDepartamentosRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listMyDepartamentos, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> updateMyDepartamento(
    $0.UpdateMyDepartamentoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$updateMyDepartamento, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> desativarMyDepartamento(
    $0.MyDepartamentoIdRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$desativarMyDepartamento, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.ListMyAtendentesResponse> listMyAtendentes(
    $0.ListMyAtendentesRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listMyAtendentes, request, options: options);
  }

  $grpc.ResponseFuture<$0.MyAtendenteResponse> createMyAtendente(
    $0.CreateMyAtendenteRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createMyAtendente, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> updateMyAtendente(
    $0.UpdateMyAtendenteRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$updateMyAtendente, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> desativarMyAtendente(
    $0.MyAtendenteIdRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$desativarMyAtendente, request, options: options);
  }

  $grpc.ResponseFuture<$0.GetMyPainelResponse> getMyPainel(
    $0.GetMyPainelRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getMyPainel, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListMyContatosResponse> listMyContatos(
    $0.ListMyContatosRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listMyContatos, request, options: options);
  }

  /// C4 — cadastro de contato pela tela. Ate aqui um contato so existia
  /// porque mandou mensagem, e o "iniciar atendimento" do C3 nao achava
  /// ninguem para escolher.
  $grpc.ResponseFuture<$0.MyContatoResponse> createMyContato(
    $0.CreateMyContatoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createMyContato, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> updateMyContato(
    $0.UpdateMyContatoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$updateMyContato, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> definirMyContatoAtivo(
    $0.DefinirMyContatoAtivoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$definirMyContatoAtivo, request, options: options);
  }

  /// B10 (N11 E5): clientes (PJ/PF) e o vinculo com os contatos.
  $grpc.ResponseFuture<$0.ListMyClientesResponse> listMyClientes(
    $0.ListMyClientesRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listMyClientes, request, options: options);
  }

  $grpc.ResponseFuture<$0.MyClienteResponse> createMyCliente(
    $0.CreateMyClienteRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createMyCliente, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> updateMyCliente(
    $0.UpdateMyClienteRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$updateMyCliente, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> definirMyClienteAtivo(
    $0.DefinirMyClienteAtivoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$definirMyClienteAtivo, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListMyContatosDoClienteResponse>
      listMyContatosDoCliente(
    $0.MyClienteIdRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listMyContatosDoCliente, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> vincularMyContatoCliente(
    $0.VincularMyContatoClienteRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$vincularMyContatoCliente, request,
        options: options);
  }

  /// N9 E13 — o catalogo de campos do cartao, por tenant.
  $grpc.ResponseFuture<$0.ListMyCamposResponse> listMyCampos(
    $0.ListMyCamposRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listMyCampos, request, options: options);
  }

  $grpc.ResponseFuture<$0.MyCampoResponse> createMyCampo(
    $0.CreateMyCampoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createMyCampo, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> updateMyCampo(
    $0.UpdateMyCampoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$updateMyCampo, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> desativarMyCampo(
    $0.MyCampoIdRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$desativarMyCampo, request, options: options);
  }

  /// Preenchimento manual na ficha do atendimento.
  $grpc.ResponseFuture<$0.SimpleOkResponse> setMyValorCampo(
    $0.SetMyValorCampoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setMyValorCampo, request, options: options);
  }

  /// Fluxos de atendimento e suas etapas — o quadro por onde a conversa anda.
  $grpc.ResponseFuture<$0.ListMyFluxosResponse> listMyFluxos(
    $0.ListMyFluxosRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listMyFluxos, request, options: options);
  }

  $grpc.ResponseFuture<$0.MyFluxoResponse> createMyFluxo(
    $0.CreateMyFluxoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createMyFluxo, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> updateMyFluxo(
    $0.UpdateMyFluxoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$updateMyFluxo, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> desativarMyFluxo(
    $0.MyFluxoIdRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$desativarMyFluxo, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListMyEtapasFluxoResponse> listMyEtapasFluxo(
    $0.MyFluxoIdRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listMyEtapasFluxo, request, options: options);
  }

  $grpc.ResponseFuture<$0.MyEtapaFluxoResponse> createMyEtapaFluxo(
    $0.CreateMyEtapaFluxoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createMyEtapaFluxo, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> updateMyEtapaFluxo(
    $0.UpdateMyEtapaFluxoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$updateMyEtapaFluxo, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> desativarMyEtapaFluxo(
    $0.MyEtapaFluxoIdRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$desativarMyEtapaFluxo, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> moverMyEtapaFluxo(
    $0.MoverMyEtapaFluxoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$moverMyEtapaFluxo, request, options: options);
  }

  // method descriptors

  static final _$listCoreSettings = $grpc.ClientMethod<
          $0.ListCoreSettingsRequest, $0.ListCoreSettingsResponse>(
      '/smartcore.contracts.queries.AdminService/ListCoreSettings',
      ($0.ListCoreSettingsRequest value) => value.writeToBuffer(),
      $0.ListCoreSettingsResponse.fromBuffer);
  static final _$upsertCoreSetting = $grpc.ClientMethod<
          $0.UpsertCoreSettingRequest, $0.UpsertCoreSettingResponse>(
      '/smartcore.contracts.queries.AdminService/UpsertCoreSetting',
      ($0.UpsertCoreSettingRequest value) => value.writeToBuffer(),
      $0.UpsertCoreSettingResponse.fromBuffer);
  static final _$deleteCoreSetting = $grpc.ClientMethod<
          $0.DeleteCoreSettingRequest, $0.DeleteCoreSettingResponse>(
      '/smartcore.contracts.queries.AdminService/DeleteCoreSetting',
      ($0.DeleteCoreSettingRequest value) => value.writeToBuffer(),
      $0.DeleteCoreSettingResponse.fromBuffer);
  static final _$getTenantConfig =
      $grpc.ClientMethod<$0.GetTenantConfigRequest, $0.GetTenantConfigResponse>(
          '/smartcore.contracts.queries.AdminService/GetTenantConfig',
          ($0.GetTenantConfigRequest value) => value.writeToBuffer(),
          $0.GetTenantConfigResponse.fromBuffer);
  static final _$updateTenantConfig = $grpc.ClientMethod<
          $0.UpdateTenantConfigRequest, $0.UpdateTenantConfigResponse>(
      '/smartcore.contracts.queries.AdminService/UpdateTenantConfig',
      ($0.UpdateTenantConfigRequest value) => value.writeToBuffer(),
      $0.UpdateTenantConfigResponse.fromBuffer);
  static final _$adminListUsers =
      $grpc.ClientMethod<$0.AdminListUsersRequest, $0.AdminListUsersResponse>(
          '/smartcore.contracts.queries.AdminService/AdminListUsers',
          ($0.AdminListUsersRequest value) => value.writeToBuffer(),
          $0.AdminListUsersResponse.fromBuffer);
  static final _$adminSetUserActive = $grpc.ClientMethod<
          $0.AdminSetUserActiveRequest, $0.AdminSetUserActiveResponse>(
      '/smartcore.contracts.queries.AdminService/AdminSetUserActive',
      ($0.AdminSetUserActiveRequest value) => value.writeToBuffer(),
      $0.AdminSetUserActiveResponse.fromBuffer);
  static final _$listTenants =
      $grpc.ClientMethod<$0.ListTenantsRequest, $0.ListTenantsResponse>(
          '/smartcore.contracts.queries.AdminService/ListTenants',
          ($0.ListTenantsRequest value) => value.writeToBuffer(),
          $0.ListTenantsResponse.fromBuffer);
  static final _$getTenant =
      $grpc.ClientMethod<$0.GetTenantRequest, $0.GetTenantResponse>(
          '/smartcore.contracts.queries.AdminService/GetTenant',
          ($0.GetTenantRequest value) => value.writeToBuffer(),
          $0.GetTenantResponse.fromBuffer);
  static final _$createTenant =
      $grpc.ClientMethod<$0.CreateTenantRequest, $0.CreateTenantResponse>(
          '/smartcore.contracts.queries.AdminService/CreateTenant',
          ($0.CreateTenantRequest value) => value.writeToBuffer(),
          $0.CreateTenantResponse.fromBuffer);
  static final _$updateTenant =
      $grpc.ClientMethod<$0.UpdateTenantRequest, $0.UpdateTenantResponse>(
          '/smartcore.contracts.queries.AdminService/UpdateTenant',
          ($0.UpdateTenantRequest value) => value.writeToBuffer(),
          $0.UpdateTenantResponse.fromBuffer);
  static final _$setTenantActive =
      $grpc.ClientMethod<$0.SetTenantActiveRequest, $0.SetTenantActiveResponse>(
          '/smartcore.contracts.queries.AdminService/SetTenantActive',
          ($0.SetTenantActiveRequest value) => value.writeToBuffer(),
          $0.SetTenantActiveResponse.fromBuffer);
  static final _$generateAccessCode = $grpc.ClientMethod<
          $0.GenerateAccessCodeRequest, $0.GenerateAccessCodeResponse>(
      '/smartcore.contracts.queries.AdminService/GenerateAccessCode',
      ($0.GenerateAccessCodeRequest value) => value.writeToBuffer(),
      $0.GenerateAccessCodeResponse.fromBuffer);
  static final _$listPlans =
      $grpc.ClientMethod<$0.ListPlansRequest, $0.ListPlansResponse>(
          '/smartcore.contracts.queries.AdminService/ListPlans',
          ($0.ListPlansRequest value) => value.writeToBuffer(),
          $0.ListPlansResponse.fromBuffer);
  static final _$createPlan =
      $grpc.ClientMethod<$0.CreatePlanRequest, $0.CreatePlanResponse>(
          '/smartcore.contracts.queries.AdminService/CreatePlan',
          ($0.CreatePlanRequest value) => value.writeToBuffer(),
          $0.CreatePlanResponse.fromBuffer);
  static final _$updatePlan =
      $grpc.ClientMethod<$0.UpdatePlanRequest, $0.UpdatePlanResponse>(
          '/smartcore.contracts.queries.AdminService/UpdatePlan',
          ($0.UpdatePlanRequest value) => value.writeToBuffer(),
          $0.UpdatePlanResponse.fromBuffer);
  static final _$listSubscriptions = $grpc.ClientMethod<
          $0.ListSubscriptionsRequest, $0.ListSubscriptionsResponse>(
      '/smartcore.contracts.queries.AdminService/ListSubscriptions',
      ($0.ListSubscriptionsRequest value) => value.writeToBuffer(),
      $0.ListSubscriptionsResponse.fromBuffer);
  static final _$registerPayment =
      $grpc.ClientMethod<$0.RegisterPaymentRequest, $0.RegisterPaymentResponse>(
          '/smartcore.contracts.queries.AdminService/RegisterPayment',
          ($0.RegisterPaymentRequest value) => value.writeToBuffer(),
          $0.RegisterPaymentResponse.fromBuffer);
  static final _$listPayments =
      $grpc.ClientMethod<$0.ListPaymentsRequest, $0.ListPaymentsResponse>(
          '/smartcore.contracts.queries.AdminService/ListPayments',
          ($0.ListPaymentsRequest value) => value.writeToBuffer(),
          $0.ListPaymentsResponse.fromBuffer);
  static final _$listVouchers =
      $grpc.ClientMethod<$0.ListVouchersRequest, $0.ListVouchersResponse>(
          '/smartcore.contracts.queries.AdminService/ListVouchers',
          ($0.ListVouchersRequest value) => value.writeToBuffer(),
          $0.ListVouchersResponse.fromBuffer);
  static final _$createVoucher =
      $grpc.ClientMethod<$0.CreateVoucherRequest, $0.CreateVoucherResponse>(
          '/smartcore.contracts.queries.AdminService/CreateVoucher',
          ($0.CreateVoucherRequest value) => value.writeToBuffer(),
          $0.CreateVoucherResponse.fromBuffer);
  static final _$revokeVoucher =
      $grpc.ClientMethod<$0.RevokeVoucherRequest, $0.RevokeVoucherResponse>(
          '/smartcore.contracts.queries.AdminService/RevokeVoucher',
          ($0.RevokeVoucherRequest value) => value.writeToBuffer(),
          $0.RevokeVoucherResponse.fromBuffer);
  static final _$listVoucherRedemptions = $grpc.ClientMethod<
          $0.ListVoucherRedemptionsRequest, $0.ListVoucherRedemptionsResponse>(
      '/smartcore.contracts.queries.AdminService/ListVoucherRedemptions',
      ($0.ListVoucherRedemptionsRequest value) => value.writeToBuffer(),
      $0.ListVoucherRedemptionsResponse.fromBuffer);
  static final _$testEvolutionConnection = $grpc.ClientMethod<
          $0.TestEvolutionConnectionRequest,
          $0.TestEvolutionConnectionResponse>(
      '/smartcore.contracts.queries.AdminService/TestEvolutionConnection',
      ($0.TestEvolutionConnectionRequest value) => value.writeToBuffer(),
      $0.TestEvolutionConnectionResponse.fromBuffer);
  static final _$testarProvedorIa = $grpc.ClientMethod<
          $0.TestarProvedorIaRequest, $0.TestarProvedorIaResponse>(
      '/smartcore.contracts.queries.AdminService/TestarProvedorIa',
      ($0.TestarProvedorIaRequest value) => value.writeToBuffer(),
      $0.TestarProvedorIaResponse.fromBuffer);
  static final _$listFeatureFlags = $grpc.ClientMethod<
          $0.ListFeatureFlagsRequest, $0.ListFeatureFlagsResponse>(
      '/smartcore.contracts.queries.AdminService/ListFeatureFlags',
      ($0.ListFeatureFlagsRequest value) => value.writeToBuffer(),
      $0.ListFeatureFlagsResponse.fromBuffer);
  static final _$setFeatureFlag =
      $grpc.ClientMethod<$0.SetFeatureFlagRequest, $0.SetFeatureFlagResponse>(
          '/smartcore.contracts.queries.AdminService/SetFeatureFlag',
          ($0.SetFeatureFlagRequest value) => value.writeToBuffer(),
          $0.SetFeatureFlagResponse.fromBuffer);
  static final _$setFeatureFlagOverride = $grpc.ClientMethod<
          $0.SetFeatureFlagOverrideRequest, $0.SetFeatureFlagOverrideResponse>(
      '/smartcore.contracts.queries.AdminService/SetFeatureFlagOverride',
      ($0.SetFeatureFlagOverrideRequest value) => value.writeToBuffer(),
      $0.SetFeatureFlagOverrideResponse.fromBuffer);
  static final _$queryAuditLog =
      $grpc.ClientMethod<$0.QueryAuditLogRequest, $0.QueryAuditLogResponse>(
          '/smartcore.contracts.queries.AdminService/QueryAuditLog',
          ($0.QueryAuditLogRequest value) => value.writeToBuffer(),
          $0.QueryAuditLogResponse.fromBuffer);
  static final _$getServiceHealth = $grpc.ClientMethod<
          $0.GetServiceHealthRequest, $0.GetServiceHealthResponse>(
      '/smartcore.contracts.queries.AdminService/GetServiceHealth',
      ($0.GetServiceHealthRequest value) => value.writeToBuffer(),
      $0.GetServiceHealthResponse.fromBuffer);
  static final _$getDashboardSummary = $grpc.ClientMethod<
          $0.GetDashboardSummaryRequest, $0.GetDashboardSummaryResponse>(
      '/smartcore.contracts.queries.AdminService/GetDashboardSummary',
      ($0.GetDashboardSummaryRequest value) => value.writeToBuffer(),
      $0.GetDashboardSummaryResponse.fromBuffer);
  static final _$exportTenantsCsv = $grpc.ClientMethod<
          $0.ExportTenantsCsvRequest, $0.ExportTenantsCsvResponse>(
      '/smartcore.contracts.queries.AdminService/ExportTenantsCsv',
      ($0.ExportTenantsCsvRequest value) => value.writeToBuffer(),
      $0.ExportTenantsCsvResponse.fromBuffer);
  static final _$streamAtendimentos =
      $grpc.ClientMethod<$0.StreamAtendimentosRequest, $0.AtendimentoEvent>(
          '/smartcore.contracts.queries.AdminService/StreamAtendimentos',
          ($0.StreamAtendimentosRequest value) => value.writeToBuffer(),
          $0.AtendimentoEvent.fromBuffer);
  static final _$listAtendimentos = $grpc.ClientMethod<
          $0.ListAtendimentosRequest, $0.ListAtendimentosResponse>(
      '/smartcore.contracts.queries.AdminService/ListAtendimentos',
      ($0.ListAtendimentosRequest value) => value.writeToBuffer(),
      $0.ListAtendimentosResponse.fromBuffer);
  static final _$getThread =
      $grpc.ClientMethod<$0.GetThreadRequest, $0.GetThreadResponse>(
          '/smartcore.contracts.queries.AdminService/GetThread',
          ($0.GetThreadRequest value) => value.writeToBuffer(),
          $0.GetThreadResponse.fromBuffer);
  static final _$iniciarAtendimentoManual = $grpc.ClientMethod<
          $0.IniciarAtendimentoManualRequest,
          $0.IniciarAtendimentoManualResponse>(
      '/smartcore.contracts.queries.AdminService/IniciarAtendimentoManual',
      ($0.IniciarAtendimentoManualRequest value) => value.writeToBuffer(),
      $0.IniciarAtendimentoManualResponse.fromBuffer);
  static final _$moveAtendimentoEtapa = $grpc.ClientMethod<
          $0.MoveAtendimentoEtapaRequest, $0.MoveAtendimentoEtapaResponse>(
      '/smartcore.contracts.queries.AdminService/MoveAtendimentoEtapa',
      ($0.MoveAtendimentoEtapaRequest value) => value.writeToBuffer(),
      $0.MoveAtendimentoEtapaResponse.fromBuffer);
  static final _$setAtendimentoStatus = $grpc.ClientMethod<
          $0.SetAtendimentoStatusRequest, $0.SetAtendimentoStatusResponse>(
      '/smartcore.contracts.queries.AdminService/SetAtendimentoStatus',
      ($0.SetAtendimentoStatusRequest value) => value.writeToBuffer(),
      $0.SetAtendimentoStatusResponse.fromBuffer);
  static final _$getDetalheAtendimento = $grpc.ClientMethod<
          $0.AtendimentoIdRequest, $0.DetalheAtendimentoResponse>(
      '/smartcore.contracts.queries.AdminService/GetDetalheAtendimento',
      ($0.AtendimentoIdRequest value) => value.writeToBuffer(),
      $0.DetalheAtendimentoResponse.fromBuffer);
  static final _$createEtiqueta =
      $grpc.ClientMethod<$0.CreateEtiquetaRequest, $0.EtiquetaResponse>(
          '/smartcore.contracts.queries.AdminService/CreateEtiqueta',
          ($0.CreateEtiquetaRequest value) => value.writeToBuffer(),
          $0.EtiquetaResponse.fromBuffer);
  static final _$alternarEtiqueta =
      $grpc.ClientMethod<$0.AlternarEtiquetaRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/AlternarEtiqueta',
          ($0.AlternarEtiquetaRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$createNota =
      $grpc.ClientMethod<$0.CreateNotaRequest, $0.NotaResponse>(
          '/smartcore.contracts.queries.AdminService/CreateNota',
          ($0.CreateNotaRequest value) => value.writeToBuffer(),
          $0.NotaResponse.fromBuffer);
  static final _$sendOutboundMessage = $grpc.ClientMethod<
          $0.SendOutboundMessageRequest, $0.SendOutboundMessageResponse>(
      '/smartcore.contracts.queries.AdminService/SendOutboundMessage',
      ($0.SendOutboundMessageRequest value) => value.writeToBuffer(),
      $0.SendOutboundMessageResponse.fromBuffer);
  static final _$solicitarUploadMidia = $grpc.ClientMethod<
          $0.SolicitarUploadMidiaRequest, $0.SolicitarUploadMidiaResponse>(
      '/smartcore.contracts.queries.AdminService/SolicitarUploadMidia',
      ($0.SolicitarUploadMidiaRequest value) => value.writeToBuffer(),
      $0.SolicitarUploadMidiaResponse.fromBuffer);
  static final _$enviarMidiaAtendimento = $grpc.ClientMethod<
          $0.EnviarMidiaAtendimentoRequest, $0.EnviarMidiaAtendimentoResponse>(
      '/smartcore.contracts.queries.AdminService/EnviarMidiaAtendimento',
      ($0.EnviarMidiaAtendimentoRequest value) => value.writeToBuffer(),
      $0.EnviarMidiaAtendimentoResponse.fromBuffer);
  static final _$listarMidiasAtendimento = $grpc.ClientMethod<
          $0.ListarMidiasAtendimentoRequest,
          $0.ListarMidiasAtendimentoResponse>(
      '/smartcore.contracts.queries.AdminService/ListarMidiasAtendimento',
      ($0.ListarMidiasAtendimentoRequest value) => value.writeToBuffer(),
      $0.ListarMidiasAtendimentoResponse.fromBuffer);
  static final _$enviarPresenca =
      $grpc.ClientMethod<$0.EnviarPresencaRequest, $0.EnviarPresencaResponse>(
          '/smartcore.contracts.queries.AdminService/EnviarPresenca',
          ($0.EnviarPresencaRequest value) => value.writeToBuffer(),
          $0.EnviarPresencaResponse.fromBuffer);
  static final _$listarTimelineAtendimento =
      $grpc.ClientMethod<$0.ListarTimelineRequest, $0.ListarTimelineResponse>(
          '/smartcore.contracts.queries.AdminService/ListarTimelineAtendimento',
          ($0.ListarTimelineRequest value) => value.writeToBuffer(),
          $0.ListarTimelineResponse.fromBuffer);
  static final _$listarAtendimentosDoContato = $grpc.ClientMethod<
          $0.ListarAtendimentosDoContatoRequest,
          $0.ListarAtendimentosDoContatoResponse>(
      '/smartcore.contracts.queries.AdminService/ListarAtendimentosDoContato',
      ($0.ListarAtendimentosDoContatoRequest value) => value.writeToBuffer(),
      $0.ListarAtendimentosDoContatoResponse.fromBuffer);
  static final _$removerNota =
      $grpc.ClientMethod<$0.RemoverNotaRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/RemoverNota',
          ($0.RemoverNotaRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$updateEtiqueta =
      $grpc.ClientMethod<$0.UpdateEtiquetaRequest, $0.EtiquetaResponse>(
          '/smartcore.contracts.queries.AdminService/UpdateEtiqueta',
          ($0.UpdateEtiquetaRequest value) => value.writeToBuffer(),
          $0.EtiquetaResponse.fromBuffer);
  static final _$desativarEtiqueta =
      $grpc.ClientMethod<$0.DesativarEtiquetaRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/DesativarEtiqueta',
          ($0.DesativarEtiquetaRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$atribuirAtendimento = $grpc.ClientMethod<
          $0.AtribuirAtendimentoRequest, $0.AtribuirAtendimentoResponse>(
      '/smartcore.contracts.queries.AdminService/AtribuirAtendimento',
      ($0.AtribuirAtendimentoRequest value) => value.writeToBuffer(),
      $0.AtribuirAtendimentoResponse.fromBuffer);
  static final _$definirPrioridade = $grpc.ClientMethod<
          $0.DefinirPrioridadeRequest, $0.DefinirPrioridadeResponse>(
      '/smartcore.contracts.queries.AdminService/DefinirPrioridade',
      ($0.DefinirPrioridadeRequest value) => value.writeToBuffer(),
      $0.DefinirPrioridadeResponse.fromBuffer);
  static final _$transferirParaFluxo = $grpc.ClientMethod<
          $0.TransferirParaFluxoRequest, $0.TransferirParaFluxoResponse>(
      '/smartcore.contracts.queries.AdminService/TransferirParaFluxo',
      ($0.TransferirParaFluxoRequest value) => value.writeToBuffer(),
      $0.TransferirParaFluxoResponse.fromBuffer);
  static final _$exportarQuadro =
      $grpc.ClientMethod<$0.ExportarQuadroRequest, $0.ExportarQuadroResponse>(
          '/smartcore.contracts.queries.AdminService/ExportarQuadro',
          ($0.ExportarQuadroRequest value) => value.writeToBuffer(),
          $0.ExportarQuadroResponse.fromBuffer);
  static final _$createInvite =
      $grpc.ClientMethod<$0.CreateInviteRequest, $0.CreateInviteResponse>(
          '/smartcore.contracts.queries.AdminService/CreateInvite',
          ($0.CreateInviteRequest value) => value.writeToBuffer(),
          $0.CreateInviteResponse.fromBuffer);
  static final _$acceptInvite =
      $grpc.ClientMethod<$0.AcceptInviteRequest, $0.AcceptInviteResponse>(
          '/smartcore.contracts.queries.AdminService/AcceptInvite',
          ($0.AcceptInviteRequest value) => value.writeToBuffer(),
          $0.AcceptInviteResponse.fromBuffer);
  static final _$listInvites =
      $grpc.ClientMethod<$0.ListInvitesRequest, $0.ListInvitesResponse>(
          '/smartcore.contracts.queries.AdminService/ListInvites',
          ($0.ListInvitesRequest value) => value.writeToBuffer(),
          $0.ListInvitesResponse.fromBuffer);
  static final _$revokeInvite =
      $grpc.ClientMethod<$0.RevokeInviteRequest, $0.RevokeInviteResponse>(
          '/smartcore.contracts.queries.AdminService/RevokeInvite',
          ($0.RevokeInviteRequest value) => value.writeToBuffer(),
          $0.RevokeInviteResponse.fromBuffer);
  static final _$reenviarConvite =
      $grpc.ClientMethod<$0.ReenviarConviteRequest, $0.ReenviarConviteResponse>(
          '/smartcore.contracts.queries.AdminService/ReenviarConvite',
          ($0.ReenviarConviteRequest value) => value.writeToBuffer(),
          $0.ReenviarConviteResponse.fromBuffer);
  static final _$listTenantUsers =
      $grpc.ClientMethod<$0.ListTenantUsersRequest, $0.ListTenantUsersResponse>(
          '/smartcore.contracts.queries.AdminService/ListTenantUsers',
          ($0.ListTenantUsersRequest value) => value.writeToBuffer(),
          $0.ListTenantUsersResponse.fromBuffer);
  static final _$updateTenantUser = $grpc.ClientMethod<
          $0.UpdateTenantUserRequest, $0.UpdateTenantUserResponse>(
      '/smartcore.contracts.queries.AdminService/UpdateTenantUser',
      ($0.UpdateTenantUserRequest value) => value.writeToBuffer(),
      $0.UpdateTenantUserResponse.fromBuffer);
  static final _$getMyTenantConfig = $grpc.ClientMethod<
          $0.GetMyTenantConfigRequest, $0.GetTenantConfigResponse>(
      '/smartcore.contracts.queries.AdminService/GetMyTenantConfig',
      ($0.GetMyTenantConfigRequest value) => value.writeToBuffer(),
      $0.GetTenantConfigResponse.fromBuffer);
  static final _$updateMyTenantConfig = $grpc.ClientMethod<
          $0.UpdateMyTenantConfigRequest, $0.UpdateTenantConfigResponse>(
      '/smartcore.contracts.queries.AdminService/UpdateMyTenantConfig',
      ($0.UpdateMyTenantConfigRequest value) => value.writeToBuffer(),
      $0.UpdateTenantConfigResponse.fromBuffer);
  static final _$listMcpGrants =
      $grpc.ClientMethod<$0.ListMcpGrantsRequest, $0.ListMcpGrantsResponse>(
          '/smartcore.contracts.queries.AdminService/ListMcpGrants',
          ($0.ListMcpGrantsRequest value) => value.writeToBuffer(),
          $0.ListMcpGrantsResponse.fromBuffer);
  static final _$revokeMcpGrant =
      $grpc.ClientMethod<$0.RevokeMcpGrantRequest, $0.RevokeMcpGrantResponse>(
          '/smartcore.contracts.queries.AdminService/RevokeMcpGrant',
          ($0.RevokeMcpGrantRequest value) => value.writeToBuffer(),
          $0.RevokeMcpGrantResponse.fromBuffer);
  static final _$ajustarEscoposMcpGrant = $grpc.ClientMethod<
          $0.AjustarEscoposMcpGrantRequest, $0.AjustarEscoposMcpGrantResponse>(
      '/smartcore.contracts.queries.AdminService/AjustarEscoposMcpGrant',
      ($0.AjustarEscoposMcpGrantRequest value) => value.writeToBuffer(),
      $0.AjustarEscoposMcpGrantResponse.fromBuffer);
  static final _$listMyAuditLog =
      $grpc.ClientMethod<$0.ListMyAuditLogRequest, $0.ListMyAuditLogResponse>(
          '/smartcore.contracts.queries.AdminService/ListMyAuditLog',
          ($0.ListMyAuditLogRequest value) => value.writeToBuffer(),
          $0.ListMyAuditLogResponse.fromBuffer);
  static final _$createMyWhatsappInstance = $grpc.ClientMethod<
          $0.CreateMyWhatsappInstanceRequest,
          $0.CreateMyWhatsappInstanceResponse>(
      '/smartcore.contracts.queries.AdminService/CreateMyWhatsappInstance',
      ($0.CreateMyWhatsappInstanceRequest value) => value.writeToBuffer(),
      $0.CreateMyWhatsappInstanceResponse.fromBuffer);
  static final _$getMyWhatsappInstanceStatus = $grpc.ClientMethod<
          $0.GetMyWhatsappInstanceStatusRequest,
          $0.GetMyWhatsappInstanceStatusResponse>(
      '/smartcore.contracts.queries.AdminService/GetMyWhatsappInstanceStatus',
      ($0.GetMyWhatsappInstanceStatusRequest value) => value.writeToBuffer(),
      $0.GetMyWhatsappInstanceStatusResponse.fromBuffer);
  static final _$createMyDepartamento = $grpc.ClientMethod<
          $0.CreateMyDepartamentoRequest, $0.CreateMyDepartamentoResponse>(
      '/smartcore.contracts.queries.AdminService/CreateMyDepartamento',
      ($0.CreateMyDepartamentoRequest value) => value.writeToBuffer(),
      $0.CreateMyDepartamentoResponse.fromBuffer);
  static final _$setMyBotPersona =
      $grpc.ClientMethod<$0.SetMyBotPersonaRequest, $0.SetMyBotPersonaResponse>(
          '/smartcore.contracts.queries.AdminService/SetMyBotPersona',
          ($0.SetMyBotPersonaRequest value) => value.writeToBuffer(),
          $0.SetMyBotPersonaResponse.fromBuffer);
  static final _$setOnboardingProgress = $grpc.ClientMethod<
          $0.SetOnboardingProgressRequest, $0.SetOnboardingProgressResponse>(
      '/smartcore.contracts.queries.AdminService/SetOnboardingProgress',
      ($0.SetOnboardingProgressRequest value) => value.writeToBuffer(),
      $0.SetOnboardingProgressResponse.fromBuffer);
  static final _$getMyOnboardingProgress = $grpc.ClientMethod<
          $0.GetMyOnboardingProgressRequest,
          $0.GetMyOnboardingProgressResponse>(
      '/smartcore.contracts.queries.AdminService/GetMyOnboardingProgress',
      ($0.GetMyOnboardingProgressRequest value) => value.writeToBuffer(),
      $0.GetMyOnboardingProgressResponse.fromBuffer);
  static final _$quitarMinhaAssinatura = $grpc.ClientMethod<
          $0.QuitarMinhaAssinaturaRequest, $0.QuitarMinhaAssinaturaResponse>(
      '/smartcore.contracts.queries.AdminService/QuitarMinhaAssinatura',
      ($0.QuitarMinhaAssinaturaRequest value) => value.writeToBuffer(),
      $0.QuitarMinhaAssinaturaResponse.fromBuffer);
  static final _$createMyTreinamento = $grpc.ClientMethod<
          $0.CreateMyTreinamentoRequest, $0.MyTreinamentoResponse>(
      '/smartcore.contracts.queries.AdminService/CreateMyTreinamento',
      ($0.CreateMyTreinamentoRequest value) => value.writeToBuffer(),
      $0.MyTreinamentoResponse.fromBuffer);
  static final _$listMyTreinamentos = $grpc.ClientMethod<
          $0.ListMyTreinamentosRequest, $0.ListMyTreinamentosResponse>(
      '/smartcore.contracts.queries.AdminService/ListMyTreinamentos',
      ($0.ListMyTreinamentosRequest value) => value.writeToBuffer(),
      $0.ListMyTreinamentosResponse.fromBuffer);
  static final _$listMyIntents =
      $grpc.ClientMethod<$0.ListMyIntentsRequest, $0.ListMyIntentsResponse>(
          '/smartcore.contracts.queries.AdminService/ListMyIntents',
          ($0.ListMyIntentsRequest value) => value.writeToBuffer(),
          $0.ListMyIntentsResponse.fromBuffer);
  static final _$createMyIntent =
      $grpc.ClientMethod<$0.MyIntentDados, $0.MyIntentResponse>(
          '/smartcore.contracts.queries.AdminService/CreateMyIntent',
          ($0.MyIntentDados value) => value.writeToBuffer(),
          $0.MyIntentResponse.fromBuffer);
  static final _$updateMyIntent =
      $grpc.ClientMethod<$0.UpdateMyIntentRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/UpdateMyIntent',
          ($0.UpdateMyIntentRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$removeMyIntent =
      $grpc.ClientMethod<$0.MyIntentIdRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/RemoveMyIntent',
          ($0.MyIntentIdRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$testarPergunta =
      $grpc.ClientMethod<$0.TestarPerguntaRequest, $0.TestarPerguntaResponse>(
          '/smartcore.contracts.queries.AdminService/TestarPergunta',
          ($0.TestarPerguntaRequest value) => value.writeToBuffer(),
          $0.TestarPerguntaResponse.fromBuffer);
  static final _$solicitarUploadTreinamento = $grpc.ClientMethod<
          $0.SolicitarUploadTreinamentoRequest,
          $0.SolicitarUploadTreinamentoResponse>(
      '/smartcore.contracts.queries.AdminService/SolicitarUploadTreinamento',
      ($0.SolicitarUploadTreinamentoRequest value) => value.writeToBuffer(),
      $0.SolicitarUploadTreinamentoResponse.fromBuffer);
  static final _$createMyTreinamentoComArquivo = $grpc.ClientMethod<
          $0.CreateMyTreinamentoComArquivoRequest, $0.MyTreinamentoResponse>(
      '/smartcore.contracts.queries.AdminService/CreateMyTreinamentoComArquivo',
      ($0.CreateMyTreinamentoComArquivoRequest value) => value.writeToBuffer(),
      $0.MyTreinamentoResponse.fromBuffer);
  static final _$registrarFeedbackTeste = $grpc.ClientMethod<
          $0.RegistrarFeedbackTesteRequest, $0.RegistrarFeedbackTesteResponse>(
      '/smartcore.contracts.queries.AdminService/RegistrarFeedbackTeste',
      ($0.RegistrarFeedbackTesteRequest value) => value.writeToBuffer(),
      $0.RegistrarFeedbackTesteResponse.fromBuffer);
  static final _$getMyTreinamento =
      $grpc.ClientMethod<$0.GetMyTreinamentoRequest, $0.MyTreinamentoResponse>(
          '/smartcore.contracts.queries.AdminService/GetMyTreinamento',
          ($0.GetMyTreinamentoRequest value) => value.writeToBuffer(),
          $0.MyTreinamentoResponse.fromBuffer);
  static final _$finalizarMyTreinamento =
      $grpc.ClientMethod<$0.FinalizarMyTreinamentoRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/FinalizarMyTreinamento',
          ($0.FinalizarMyTreinamentoRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$removerMyTreinamento =
      $grpc.ClientMethod<$0.RemoverMyTreinamentoRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/RemoverMyTreinamento',
          ($0.RemoverMyTreinamentoRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$listMyWhatsappInstances = $grpc.ClientMethod<
          $0.ListMyWhatsappInstancesRequest,
          $0.ListMyWhatsappInstancesResponse>(
      '/smartcore.contracts.queries.AdminService/ListMyWhatsappInstances',
      ($0.ListMyWhatsappInstancesRequest value) => value.writeToBuffer(),
      $0.ListMyWhatsappInstancesResponse.fromBuffer);
  static final _$definirRespostaBotInstancia = $grpc.ClientMethod<
          $0.DefinirRespostaBotInstanciaRequest,
          $0.DefinirRespostaBotInstanciaResponse>(
      '/smartcore.contracts.queries.AdminService/DefinirRespostaBotInstancia',
      ($0.DefinirRespostaBotInstanciaRequest value) => value.writeToBuffer(),
      $0.DefinirRespostaBotInstanciaResponse.fromBuffer);
  static final _$definirBotDaConversa = $grpc.ClientMethod<
          $0.DefinirBotDaConversaRequest, $0.DefinirBotDaConversaResponse>(
      '/smartcore.contracts.queries.AdminService/DefinirBotDaConversa',
      ($0.DefinirBotDaConversaRequest value) => value.writeToBuffer(),
      $0.DefinirBotDaConversaResponse.fromBuffer);
  static final _$marcarAtendimentoLido = $grpc.ClientMethod<
          $0.MarcarAtendimentoLidoRequest, $0.MarcarAtendimentoLidoResponse>(
      '/smartcore.contracts.queries.AdminService/MarcarAtendimentoLido',
      ($0.MarcarAtendimentoLidoRequest value) => value.writeToBuffer(),
      $0.MarcarAtendimentoLidoResponse.fromBuffer);
  static final _$reconnectMyWhatsappInstance = $grpc.ClientMethod<
          $0.MyWhatsappInstanceIdRequest, $0.SimpleOkResponse>(
      '/smartcore.contracts.queries.AdminService/ReconnectMyWhatsappInstance',
      ($0.MyWhatsappInstanceIdRequest value) => value.writeToBuffer(),
      $0.SimpleOkResponse.fromBuffer);
  static final _$deleteMyWhatsappInstance =
      $grpc.ClientMethod<$0.MyWhatsappInstanceIdRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/DeleteMyWhatsappInstance',
          ($0.MyWhatsappInstanceIdRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$desconectarMyWhatsappInstance = $grpc.ClientMethod<
          $0.MyWhatsappInstanceIdRequest, $0.SimpleOkResponse>(
      '/smartcore.contracts.queries.AdminService/DesconectarMyWhatsappInstance',
      ($0.MyWhatsappInstanceIdRequest value) => value.writeToBuffer(),
      $0.SimpleOkResponse.fromBuffer);
  static final _$getVersaoDoApp =
      $grpc.ClientMethod<$0.GetVersaoDoAppRequest, $0.GetVersaoDoAppResponse>(
          '/smartcore.contracts.queries.AdminService/GetVersaoDoApp',
          ($0.GetVersaoDoAppRequest value) => value.writeToBuffer(),
          $0.GetVersaoDoAppResponse.fromBuffer);
  static final _$definirDepartamentoDaConexao = $grpc.ClientMethod<
          $0.DefinirDepartamentoDaConexaoRequest, $0.SimpleOkResponse>(
      '/smartcore.contracts.queries.AdminService/DefinirDepartamentoDaConexao',
      ($0.DefinirDepartamentoDaConexaoRequest value) => value.writeToBuffer(),
      $0.SimpleOkResponse.fromBuffer);
  static final _$detalheDaConexao = $grpc.ClientMethod<
          $0.DetalheDaConexaoRequest, $0.DetalheDaConexaoResponse>(
      '/smartcore.contracts.queries.AdminService/DetalheDaConexao',
      ($0.DetalheDaConexaoRequest value) => value.writeToBuffer(),
      $0.DetalheDaConexaoResponse.fromBuffer);
  static final _$listMyMensagensNaoEntregues = $grpc.ClientMethod<
          $0.ListMyMensagensNaoEntreguesRequest,
          $0.ListMyMensagensNaoEntreguesResponse>(
      '/smartcore.contracts.queries.AdminService/ListMyMensagensNaoEntregues',
      ($0.ListMyMensagensNaoEntreguesRequest value) => value.writeToBuffer(),
      $0.ListMyMensagensNaoEntreguesResponse.fromBuffer);
  static final _$reenviarMensagemNaoEntregue = $grpc.ClientMethod<
          $0.ReenviarMensagemNaoEntregueRequest,
          $0.ReenviarMensagemNaoEntregueResponse>(
      '/smartcore.contracts.queries.AdminService/ReenviarMensagemNaoEntregue',
      ($0.ReenviarMensagemNaoEntregueRequest value) => value.writeToBuffer(),
      $0.ReenviarMensagemNaoEntregueResponse.fromBuffer);
  static final _$listMyNumerosIgnorados = $grpc.ClientMethod<
          $0.ListMyNumerosIgnoradosRequest, $0.ListMyNumerosIgnoradosResponse>(
      '/smartcore.contracts.queries.AdminService/ListMyNumerosIgnorados',
      ($0.ListMyNumerosIgnoradosRequest value) => value.writeToBuffer(),
      $0.ListMyNumerosIgnoradosResponse.fromBuffer);
  static final _$criarNumeroIgnorado = $grpc.ClientMethod<
          $0.CriarNumeroIgnoradoRequest, $0.MyNumeroIgnoradoResponse>(
      '/smartcore.contracts.queries.AdminService/CriarNumeroIgnorado',
      ($0.CriarNumeroIgnoradoRequest value) => value.writeToBuffer(),
      $0.MyNumeroIgnoradoResponse.fromBuffer);
  static final _$atualizarNumeroIgnorado = $grpc.ClientMethod<
          $0.AtualizarNumeroIgnoradoRequest, $0.SimpleOkResponse>(
      '/smartcore.contracts.queries.AdminService/AtualizarNumeroIgnorado',
      ($0.AtualizarNumeroIgnoradoRequest value) => value.writeToBuffer(),
      $0.SimpleOkResponse.fromBuffer);
  static final _$removerNumeroIgnorado =
      $grpc.ClientMethod<$0.NumeroIgnoradoIdRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/RemoverNumeroIgnorado',
          ($0.NumeroIgnoradoIdRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$listMyDepartamentos = $grpc.ClientMethod<
          $0.ListMyDepartamentosRequest, $0.ListMyDepartamentosResponse>(
      '/smartcore.contracts.queries.AdminService/ListMyDepartamentos',
      ($0.ListMyDepartamentosRequest value) => value.writeToBuffer(),
      $0.ListMyDepartamentosResponse.fromBuffer);
  static final _$updateMyDepartamento =
      $grpc.ClientMethod<$0.UpdateMyDepartamentoRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/UpdateMyDepartamento',
          ($0.UpdateMyDepartamentoRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$desativarMyDepartamento =
      $grpc.ClientMethod<$0.MyDepartamentoIdRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/DesativarMyDepartamento',
          ($0.MyDepartamentoIdRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$listMyAtendentes = $grpc.ClientMethod<
          $0.ListMyAtendentesRequest, $0.ListMyAtendentesResponse>(
      '/smartcore.contracts.queries.AdminService/ListMyAtendentes',
      ($0.ListMyAtendentesRequest value) => value.writeToBuffer(),
      $0.ListMyAtendentesResponse.fromBuffer);
  static final _$createMyAtendente =
      $grpc.ClientMethod<$0.CreateMyAtendenteRequest, $0.MyAtendenteResponse>(
          '/smartcore.contracts.queries.AdminService/CreateMyAtendente',
          ($0.CreateMyAtendenteRequest value) => value.writeToBuffer(),
          $0.MyAtendenteResponse.fromBuffer);
  static final _$updateMyAtendente =
      $grpc.ClientMethod<$0.UpdateMyAtendenteRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/UpdateMyAtendente',
          ($0.UpdateMyAtendenteRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$desativarMyAtendente =
      $grpc.ClientMethod<$0.MyAtendenteIdRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/DesativarMyAtendente',
          ($0.MyAtendenteIdRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$getMyPainel =
      $grpc.ClientMethod<$0.GetMyPainelRequest, $0.GetMyPainelResponse>(
          '/smartcore.contracts.queries.AdminService/GetMyPainel',
          ($0.GetMyPainelRequest value) => value.writeToBuffer(),
          $0.GetMyPainelResponse.fromBuffer);
  static final _$listMyContatos =
      $grpc.ClientMethod<$0.ListMyContatosRequest, $0.ListMyContatosResponse>(
          '/smartcore.contracts.queries.AdminService/ListMyContatos',
          ($0.ListMyContatosRequest value) => value.writeToBuffer(),
          $0.ListMyContatosResponse.fromBuffer);
  static final _$createMyContato =
      $grpc.ClientMethod<$0.CreateMyContatoRequest, $0.MyContatoResponse>(
          '/smartcore.contracts.queries.AdminService/CreateMyContato',
          ($0.CreateMyContatoRequest value) => value.writeToBuffer(),
          $0.MyContatoResponse.fromBuffer);
  static final _$updateMyContato =
      $grpc.ClientMethod<$0.UpdateMyContatoRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/UpdateMyContato',
          ($0.UpdateMyContatoRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$definirMyContatoAtivo =
      $grpc.ClientMethod<$0.DefinirMyContatoAtivoRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/DefinirMyContatoAtivo',
          ($0.DefinirMyContatoAtivoRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$listMyClientes =
      $grpc.ClientMethod<$0.ListMyClientesRequest, $0.ListMyClientesResponse>(
          '/smartcore.contracts.queries.AdminService/ListMyClientes',
          ($0.ListMyClientesRequest value) => value.writeToBuffer(),
          $0.ListMyClientesResponse.fromBuffer);
  static final _$createMyCliente =
      $grpc.ClientMethod<$0.CreateMyClienteRequest, $0.MyClienteResponse>(
          '/smartcore.contracts.queries.AdminService/CreateMyCliente',
          ($0.CreateMyClienteRequest value) => value.writeToBuffer(),
          $0.MyClienteResponse.fromBuffer);
  static final _$updateMyCliente =
      $grpc.ClientMethod<$0.UpdateMyClienteRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/UpdateMyCliente',
          ($0.UpdateMyClienteRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$definirMyClienteAtivo =
      $grpc.ClientMethod<$0.DefinirMyClienteAtivoRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/DefinirMyClienteAtivo',
          ($0.DefinirMyClienteAtivoRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$listMyContatosDoCliente = $grpc.ClientMethod<
          $0.MyClienteIdRequest, $0.ListMyContatosDoClienteResponse>(
      '/smartcore.contracts.queries.AdminService/ListMyContatosDoCliente',
      ($0.MyClienteIdRequest value) => value.writeToBuffer(),
      $0.ListMyContatosDoClienteResponse.fromBuffer);
  static final _$vincularMyContatoCliente = $grpc.ClientMethod<
          $0.VincularMyContatoClienteRequest, $0.SimpleOkResponse>(
      '/smartcore.contracts.queries.AdminService/VincularMyContatoCliente',
      ($0.VincularMyContatoClienteRequest value) => value.writeToBuffer(),
      $0.SimpleOkResponse.fromBuffer);
  static final _$listMyCampos =
      $grpc.ClientMethod<$0.ListMyCamposRequest, $0.ListMyCamposResponse>(
          '/smartcore.contracts.queries.AdminService/ListMyCampos',
          ($0.ListMyCamposRequest value) => value.writeToBuffer(),
          $0.ListMyCamposResponse.fromBuffer);
  static final _$createMyCampo =
      $grpc.ClientMethod<$0.CreateMyCampoRequest, $0.MyCampoResponse>(
          '/smartcore.contracts.queries.AdminService/CreateMyCampo',
          ($0.CreateMyCampoRequest value) => value.writeToBuffer(),
          $0.MyCampoResponse.fromBuffer);
  static final _$updateMyCampo =
      $grpc.ClientMethod<$0.UpdateMyCampoRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/UpdateMyCampo',
          ($0.UpdateMyCampoRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$desativarMyCampo =
      $grpc.ClientMethod<$0.MyCampoIdRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/DesativarMyCampo',
          ($0.MyCampoIdRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$setMyValorCampo =
      $grpc.ClientMethod<$0.SetMyValorCampoRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/SetMyValorCampo',
          ($0.SetMyValorCampoRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$listMyFluxos =
      $grpc.ClientMethod<$0.ListMyFluxosRequest, $0.ListMyFluxosResponse>(
          '/smartcore.contracts.queries.AdminService/ListMyFluxos',
          ($0.ListMyFluxosRequest value) => value.writeToBuffer(),
          $0.ListMyFluxosResponse.fromBuffer);
  static final _$createMyFluxo =
      $grpc.ClientMethod<$0.CreateMyFluxoRequest, $0.MyFluxoResponse>(
          '/smartcore.contracts.queries.AdminService/CreateMyFluxo',
          ($0.CreateMyFluxoRequest value) => value.writeToBuffer(),
          $0.MyFluxoResponse.fromBuffer);
  static final _$updateMyFluxo =
      $grpc.ClientMethod<$0.UpdateMyFluxoRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/UpdateMyFluxo',
          ($0.UpdateMyFluxoRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$desativarMyFluxo =
      $grpc.ClientMethod<$0.MyFluxoIdRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/DesativarMyFluxo',
          ($0.MyFluxoIdRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$listMyEtapasFluxo =
      $grpc.ClientMethod<$0.MyFluxoIdRequest, $0.ListMyEtapasFluxoResponse>(
          '/smartcore.contracts.queries.AdminService/ListMyEtapasFluxo',
          ($0.MyFluxoIdRequest value) => value.writeToBuffer(),
          $0.ListMyEtapasFluxoResponse.fromBuffer);
  static final _$createMyEtapaFluxo =
      $grpc.ClientMethod<$0.CreateMyEtapaFluxoRequest, $0.MyEtapaFluxoResponse>(
          '/smartcore.contracts.queries.AdminService/CreateMyEtapaFluxo',
          ($0.CreateMyEtapaFluxoRequest value) => value.writeToBuffer(),
          $0.MyEtapaFluxoResponse.fromBuffer);
  static final _$updateMyEtapaFluxo =
      $grpc.ClientMethod<$0.UpdateMyEtapaFluxoRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/UpdateMyEtapaFluxo',
          ($0.UpdateMyEtapaFluxoRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$desativarMyEtapaFluxo =
      $grpc.ClientMethod<$0.MyEtapaFluxoIdRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/DesativarMyEtapaFluxo',
          ($0.MyEtapaFluxoIdRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$moverMyEtapaFluxo =
      $grpc.ClientMethod<$0.MoverMyEtapaFluxoRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/MoverMyEtapaFluxo',
          ($0.MoverMyEtapaFluxoRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
}

@$pb.GrpcServiceName('smartcore.contracts.queries.AdminService')
abstract class AdminServiceBase extends $grpc.Service {
  $core.String get $name => 'smartcore.contracts.queries.AdminService';

  AdminServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.ListCoreSettingsRequest,
            $0.ListCoreSettingsResponse>(
        'ListCoreSettings',
        listCoreSettings_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListCoreSettingsRequest.fromBuffer(value),
        ($0.ListCoreSettingsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.UpsertCoreSettingRequest,
            $0.UpsertCoreSettingResponse>(
        'UpsertCoreSetting',
        upsertCoreSetting_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.UpsertCoreSettingRequest.fromBuffer(value),
        ($0.UpsertCoreSettingResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.DeleteCoreSettingRequest,
            $0.DeleteCoreSettingResponse>(
        'DeleteCoreSetting',
        deleteCoreSetting_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.DeleteCoreSettingRequest.fromBuffer(value),
        ($0.DeleteCoreSettingResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetTenantConfigRequest,
            $0.GetTenantConfigResponse>(
        'GetTenantConfig',
        getTenantConfig_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetTenantConfigRequest.fromBuffer(value),
        ($0.GetTenantConfigResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.UpdateTenantConfigRequest,
            $0.UpdateTenantConfigResponse>(
        'UpdateTenantConfig',
        updateTenantConfig_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.UpdateTenantConfigRequest.fromBuffer(value),
        ($0.UpdateTenantConfigResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.AdminListUsersRequest,
            $0.AdminListUsersResponse>(
        'AdminListUsers',
        adminListUsers_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.AdminListUsersRequest.fromBuffer(value),
        ($0.AdminListUsersResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.AdminSetUserActiveRequest,
            $0.AdminSetUserActiveResponse>(
        'AdminSetUserActive',
        adminSetUserActive_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.AdminSetUserActiveRequest.fromBuffer(value),
        ($0.AdminSetUserActiveResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.ListTenantsRequest, $0.ListTenantsResponse>(
            'ListTenants',
            listTenants_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ListTenantsRequest.fromBuffer(value),
            ($0.ListTenantsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetTenantRequest, $0.GetTenantResponse>(
        'GetTenant',
        getTenant_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.GetTenantRequest.fromBuffer(value),
        ($0.GetTenantResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.CreateTenantRequest, $0.CreateTenantResponse>(
            'CreateTenant',
            createTenant_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.CreateTenantRequest.fromBuffer(value),
            ($0.CreateTenantResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.UpdateTenantRequest, $0.UpdateTenantResponse>(
            'UpdateTenant',
            updateTenant_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.UpdateTenantRequest.fromBuffer(value),
            ($0.UpdateTenantResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SetTenantActiveRequest,
            $0.SetTenantActiveResponse>(
        'SetTenantActive',
        setTenantActive_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.SetTenantActiveRequest.fromBuffer(value),
        ($0.SetTenantActiveResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GenerateAccessCodeRequest,
            $0.GenerateAccessCodeResponse>(
        'GenerateAccessCode',
        generateAccessCode_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GenerateAccessCodeRequest.fromBuffer(value),
        ($0.GenerateAccessCodeResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListPlansRequest, $0.ListPlansResponse>(
        'ListPlans',
        listPlans_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.ListPlansRequest.fromBuffer(value),
        ($0.ListPlansResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CreatePlanRequest, $0.CreatePlanResponse>(
        'CreatePlan',
        createPlan_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.CreatePlanRequest.fromBuffer(value),
        ($0.CreatePlanResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.UpdatePlanRequest, $0.UpdatePlanResponse>(
        'UpdatePlan',
        updatePlan_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.UpdatePlanRequest.fromBuffer(value),
        ($0.UpdatePlanResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListSubscriptionsRequest,
            $0.ListSubscriptionsResponse>(
        'ListSubscriptions',
        listSubscriptions_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListSubscriptionsRequest.fromBuffer(value),
        ($0.ListSubscriptionsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.RegisterPaymentRequest,
            $0.RegisterPaymentResponse>(
        'RegisterPayment',
        registerPayment_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.RegisterPaymentRequest.fromBuffer(value),
        ($0.RegisterPaymentResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.ListPaymentsRequest, $0.ListPaymentsResponse>(
            'ListPayments',
            listPayments_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ListPaymentsRequest.fromBuffer(value),
            ($0.ListPaymentsResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.ListVouchersRequest, $0.ListVouchersResponse>(
            'ListVouchers',
            listVouchers_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ListVouchersRequest.fromBuffer(value),
            ($0.ListVouchersResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.CreateVoucherRequest, $0.CreateVoucherResponse>(
            'CreateVoucher',
            createVoucher_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.CreateVoucherRequest.fromBuffer(value),
            ($0.CreateVoucherResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.RevokeVoucherRequest, $0.RevokeVoucherResponse>(
            'RevokeVoucher',
            revokeVoucher_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.RevokeVoucherRequest.fromBuffer(value),
            ($0.RevokeVoucherResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListVoucherRedemptionsRequest,
            $0.ListVoucherRedemptionsResponse>(
        'ListVoucherRedemptions',
        listVoucherRedemptions_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListVoucherRedemptionsRequest.fromBuffer(value),
        ($0.ListVoucherRedemptionsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.TestEvolutionConnectionRequest,
            $0.TestEvolutionConnectionResponse>(
        'TestEvolutionConnection',
        testEvolutionConnection_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.TestEvolutionConnectionRequest.fromBuffer(value),
        ($0.TestEvolutionConnectionResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.TestarProvedorIaRequest,
            $0.TestarProvedorIaResponse>(
        'TestarProvedorIa',
        testarProvedorIa_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.TestarProvedorIaRequest.fromBuffer(value),
        ($0.TestarProvedorIaResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListFeatureFlagsRequest,
            $0.ListFeatureFlagsResponse>(
        'ListFeatureFlags',
        listFeatureFlags_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListFeatureFlagsRequest.fromBuffer(value),
        ($0.ListFeatureFlagsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SetFeatureFlagRequest,
            $0.SetFeatureFlagResponse>(
        'SetFeatureFlag',
        setFeatureFlag_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.SetFeatureFlagRequest.fromBuffer(value),
        ($0.SetFeatureFlagResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SetFeatureFlagOverrideRequest,
            $0.SetFeatureFlagOverrideResponse>(
        'SetFeatureFlagOverride',
        setFeatureFlagOverride_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.SetFeatureFlagOverrideRequest.fromBuffer(value),
        ($0.SetFeatureFlagOverrideResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.QueryAuditLogRequest, $0.QueryAuditLogResponse>(
            'QueryAuditLog',
            queryAuditLog_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.QueryAuditLogRequest.fromBuffer(value),
            ($0.QueryAuditLogResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetServiceHealthRequest,
            $0.GetServiceHealthResponse>(
        'GetServiceHealth',
        getServiceHealth_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetServiceHealthRequest.fromBuffer(value),
        ($0.GetServiceHealthResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetDashboardSummaryRequest,
            $0.GetDashboardSummaryResponse>(
        'GetDashboardSummary',
        getDashboardSummary_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetDashboardSummaryRequest.fromBuffer(value),
        ($0.GetDashboardSummaryResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ExportTenantsCsvRequest,
            $0.ExportTenantsCsvResponse>(
        'ExportTenantsCsv',
        exportTenantsCsv_Pre,
        false,
        true,
        ($core.List<$core.int> value) =>
            $0.ExportTenantsCsvRequest.fromBuffer(value),
        ($0.ExportTenantsCsvResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.StreamAtendimentosRequest, $0.AtendimentoEvent>(
            'StreamAtendimentos',
            streamAtendimentos_Pre,
            false,
            true,
            ($core.List<$core.int> value) =>
                $0.StreamAtendimentosRequest.fromBuffer(value),
            ($0.AtendimentoEvent value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListAtendimentosRequest,
            $0.ListAtendimentosResponse>(
        'ListAtendimentos',
        listAtendimentos_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListAtendimentosRequest.fromBuffer(value),
        ($0.ListAtendimentosResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetThreadRequest, $0.GetThreadResponse>(
        'GetThread',
        getThread_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.GetThreadRequest.fromBuffer(value),
        ($0.GetThreadResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.IniciarAtendimentoManualRequest,
            $0.IniciarAtendimentoManualResponse>(
        'IniciarAtendimentoManual',
        iniciarAtendimentoManual_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.IniciarAtendimentoManualRequest.fromBuffer(value),
        ($0.IniciarAtendimentoManualResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.MoveAtendimentoEtapaRequest,
            $0.MoveAtendimentoEtapaResponse>(
        'MoveAtendimentoEtapa',
        moveAtendimentoEtapa_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.MoveAtendimentoEtapaRequest.fromBuffer(value),
        ($0.MoveAtendimentoEtapaResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SetAtendimentoStatusRequest,
            $0.SetAtendimentoStatusResponse>(
        'SetAtendimentoStatus',
        setAtendimentoStatus_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.SetAtendimentoStatusRequest.fromBuffer(value),
        ($0.SetAtendimentoStatusResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.AtendimentoIdRequest,
            $0.DetalheAtendimentoResponse>(
        'GetDetalheAtendimento',
        getDetalheAtendimento_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.AtendimentoIdRequest.fromBuffer(value),
        ($0.DetalheAtendimentoResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.CreateEtiquetaRequest, $0.EtiquetaResponse>(
            'CreateEtiqueta',
            createEtiqueta_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.CreateEtiquetaRequest.fromBuffer(value),
            ($0.EtiquetaResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.AlternarEtiquetaRequest, $0.SimpleOkResponse>(
            'AlternarEtiqueta',
            alternarEtiqueta_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.AlternarEtiquetaRequest.fromBuffer(value),
            ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CreateNotaRequest, $0.NotaResponse>(
        'CreateNota',
        createNota_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.CreateNotaRequest.fromBuffer(value),
        ($0.NotaResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SendOutboundMessageRequest,
            $0.SendOutboundMessageResponse>(
        'SendOutboundMessage',
        sendOutboundMessage_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.SendOutboundMessageRequest.fromBuffer(value),
        ($0.SendOutboundMessageResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SolicitarUploadMidiaRequest,
            $0.SolicitarUploadMidiaResponse>(
        'SolicitarUploadMidia',
        solicitarUploadMidia_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.SolicitarUploadMidiaRequest.fromBuffer(value),
        ($0.SolicitarUploadMidiaResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.EnviarMidiaAtendimentoRequest,
            $0.EnviarMidiaAtendimentoResponse>(
        'EnviarMidiaAtendimento',
        enviarMidiaAtendimento_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.EnviarMidiaAtendimentoRequest.fromBuffer(value),
        ($0.EnviarMidiaAtendimentoResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListarMidiasAtendimentoRequest,
            $0.ListarMidiasAtendimentoResponse>(
        'ListarMidiasAtendimento',
        listarMidiasAtendimento_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListarMidiasAtendimentoRequest.fromBuffer(value),
        ($0.ListarMidiasAtendimentoResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.EnviarPresencaRequest,
            $0.EnviarPresencaResponse>(
        'EnviarPresenca',
        enviarPresenca_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.EnviarPresencaRequest.fromBuffer(value),
        ($0.EnviarPresencaResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListarTimelineRequest,
            $0.ListarTimelineResponse>(
        'ListarTimelineAtendimento',
        listarTimelineAtendimento_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListarTimelineRequest.fromBuffer(value),
        ($0.ListarTimelineResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListarAtendimentosDoContatoRequest,
            $0.ListarAtendimentosDoContatoResponse>(
        'ListarAtendimentosDoContato',
        listarAtendimentosDoContato_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListarAtendimentosDoContatoRequest.fromBuffer(value),
        ($0.ListarAtendimentosDoContatoResponse value) =>
            value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.RemoverNotaRequest, $0.SimpleOkResponse>(
        'RemoverNota',
        removerNota_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.RemoverNotaRequest.fromBuffer(value),
        ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.UpdateEtiquetaRequest, $0.EtiquetaResponse>(
            'UpdateEtiqueta',
            updateEtiqueta_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.UpdateEtiquetaRequest.fromBuffer(value),
            ($0.EtiquetaResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.DesativarEtiquetaRequest, $0.SimpleOkResponse>(
            'DesativarEtiqueta',
            desativarEtiqueta_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.DesativarEtiquetaRequest.fromBuffer(value),
            ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.AtribuirAtendimentoRequest,
            $0.AtribuirAtendimentoResponse>(
        'AtribuirAtendimento',
        atribuirAtendimento_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.AtribuirAtendimentoRequest.fromBuffer(value),
        ($0.AtribuirAtendimentoResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.DefinirPrioridadeRequest,
            $0.DefinirPrioridadeResponse>(
        'DefinirPrioridade',
        definirPrioridade_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.DefinirPrioridadeRequest.fromBuffer(value),
        ($0.DefinirPrioridadeResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.TransferirParaFluxoRequest,
            $0.TransferirParaFluxoResponse>(
        'TransferirParaFluxo',
        transferirParaFluxo_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.TransferirParaFluxoRequest.fromBuffer(value),
        ($0.TransferirParaFluxoResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ExportarQuadroRequest,
            $0.ExportarQuadroResponse>(
        'ExportarQuadro',
        exportarQuadro_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ExportarQuadroRequest.fromBuffer(value),
        ($0.ExportarQuadroResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.CreateInviteRequest, $0.CreateInviteResponse>(
            'CreateInvite',
            createInvite_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.CreateInviteRequest.fromBuffer(value),
            ($0.CreateInviteResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.AcceptInviteRequest, $0.AcceptInviteResponse>(
            'AcceptInvite',
            acceptInvite_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.AcceptInviteRequest.fromBuffer(value),
            ($0.AcceptInviteResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.ListInvitesRequest, $0.ListInvitesResponse>(
            'ListInvites',
            listInvites_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ListInvitesRequest.fromBuffer(value),
            ($0.ListInvitesResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.RevokeInviteRequest, $0.RevokeInviteResponse>(
            'RevokeInvite',
            revokeInvite_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.RevokeInviteRequest.fromBuffer(value),
            ($0.RevokeInviteResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ReenviarConviteRequest,
            $0.ReenviarConviteResponse>(
        'ReenviarConvite',
        reenviarConvite_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ReenviarConviteRequest.fromBuffer(value),
        ($0.ReenviarConviteResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListTenantUsersRequest,
            $0.ListTenantUsersResponse>(
        'ListTenantUsers',
        listTenantUsers_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListTenantUsersRequest.fromBuffer(value),
        ($0.ListTenantUsersResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.UpdateTenantUserRequest,
            $0.UpdateTenantUserResponse>(
        'UpdateTenantUser',
        updateTenantUser_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.UpdateTenantUserRequest.fromBuffer(value),
        ($0.UpdateTenantUserResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetMyTenantConfigRequest,
            $0.GetTenantConfigResponse>(
        'GetMyTenantConfig',
        getMyTenantConfig_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetMyTenantConfigRequest.fromBuffer(value),
        ($0.GetTenantConfigResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.UpdateMyTenantConfigRequest,
            $0.UpdateTenantConfigResponse>(
        'UpdateMyTenantConfig',
        updateMyTenantConfig_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.UpdateMyTenantConfigRequest.fromBuffer(value),
        ($0.UpdateTenantConfigResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.ListMcpGrantsRequest, $0.ListMcpGrantsResponse>(
            'ListMcpGrants',
            listMcpGrants_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ListMcpGrantsRequest.fromBuffer(value),
            ($0.ListMcpGrantsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.RevokeMcpGrantRequest,
            $0.RevokeMcpGrantResponse>(
        'RevokeMcpGrant',
        revokeMcpGrant_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.RevokeMcpGrantRequest.fromBuffer(value),
        ($0.RevokeMcpGrantResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.AjustarEscoposMcpGrantRequest,
            $0.AjustarEscoposMcpGrantResponse>(
        'AjustarEscoposMcpGrant',
        ajustarEscoposMcpGrant_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.AjustarEscoposMcpGrantRequest.fromBuffer(value),
        ($0.AjustarEscoposMcpGrantResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListMyAuditLogRequest,
            $0.ListMyAuditLogResponse>(
        'ListMyAuditLog',
        listMyAuditLog_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListMyAuditLogRequest.fromBuffer(value),
        ($0.ListMyAuditLogResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CreateMyWhatsappInstanceRequest,
            $0.CreateMyWhatsappInstanceResponse>(
        'CreateMyWhatsappInstance',
        createMyWhatsappInstance_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.CreateMyWhatsappInstanceRequest.fromBuffer(value),
        ($0.CreateMyWhatsappInstanceResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetMyWhatsappInstanceStatusRequest,
            $0.GetMyWhatsappInstanceStatusResponse>(
        'GetMyWhatsappInstanceStatus',
        getMyWhatsappInstanceStatus_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetMyWhatsappInstanceStatusRequest.fromBuffer(value),
        ($0.GetMyWhatsappInstanceStatusResponse value) =>
            value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CreateMyDepartamentoRequest,
            $0.CreateMyDepartamentoResponse>(
        'CreateMyDepartamento',
        createMyDepartamento_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.CreateMyDepartamentoRequest.fromBuffer(value),
        ($0.CreateMyDepartamentoResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SetMyBotPersonaRequest,
            $0.SetMyBotPersonaResponse>(
        'SetMyBotPersona',
        setMyBotPersona_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.SetMyBotPersonaRequest.fromBuffer(value),
        ($0.SetMyBotPersonaResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SetOnboardingProgressRequest,
            $0.SetOnboardingProgressResponse>(
        'SetOnboardingProgress',
        setOnboardingProgress_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.SetOnboardingProgressRequest.fromBuffer(value),
        ($0.SetOnboardingProgressResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetMyOnboardingProgressRequest,
            $0.GetMyOnboardingProgressResponse>(
        'GetMyOnboardingProgress',
        getMyOnboardingProgress_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetMyOnboardingProgressRequest.fromBuffer(value),
        ($0.GetMyOnboardingProgressResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.QuitarMinhaAssinaturaRequest,
            $0.QuitarMinhaAssinaturaResponse>(
        'QuitarMinhaAssinatura',
        quitarMinhaAssinatura_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.QuitarMinhaAssinaturaRequest.fromBuffer(value),
        ($0.QuitarMinhaAssinaturaResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CreateMyTreinamentoRequest,
            $0.MyTreinamentoResponse>(
        'CreateMyTreinamento',
        createMyTreinamento_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.CreateMyTreinamentoRequest.fromBuffer(value),
        ($0.MyTreinamentoResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListMyTreinamentosRequest,
            $0.ListMyTreinamentosResponse>(
        'ListMyTreinamentos',
        listMyTreinamentos_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListMyTreinamentosRequest.fromBuffer(value),
        ($0.ListMyTreinamentosResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.ListMyIntentsRequest, $0.ListMyIntentsResponse>(
            'ListMyIntents',
            listMyIntents_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ListMyIntentsRequest.fromBuffer(value),
            ($0.ListMyIntentsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.MyIntentDados, $0.MyIntentResponse>(
        'CreateMyIntent',
        createMyIntent_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.MyIntentDados.fromBuffer(value),
        ($0.MyIntentResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.UpdateMyIntentRequest, $0.SimpleOkResponse>(
            'UpdateMyIntent',
            updateMyIntent_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.UpdateMyIntentRequest.fromBuffer(value),
            ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.MyIntentIdRequest, $0.SimpleOkResponse>(
        'RemoveMyIntent',
        removeMyIntent_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.MyIntentIdRequest.fromBuffer(value),
        ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.TestarPerguntaRequest,
            $0.TestarPerguntaResponse>(
        'TestarPergunta',
        testarPergunta_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.TestarPerguntaRequest.fromBuffer(value),
        ($0.TestarPerguntaResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SolicitarUploadTreinamentoRequest,
            $0.SolicitarUploadTreinamentoResponse>(
        'SolicitarUploadTreinamento',
        solicitarUploadTreinamento_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.SolicitarUploadTreinamentoRequest.fromBuffer(value),
        ($0.SolicitarUploadTreinamentoResponse value) =>
            value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CreateMyTreinamentoComArquivoRequest,
            $0.MyTreinamentoResponse>(
        'CreateMyTreinamentoComArquivo',
        createMyTreinamentoComArquivo_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.CreateMyTreinamentoComArquivoRequest.fromBuffer(value),
        ($0.MyTreinamentoResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.RegistrarFeedbackTesteRequest,
            $0.RegistrarFeedbackTesteResponse>(
        'RegistrarFeedbackTeste',
        registrarFeedbackTeste_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.RegistrarFeedbackTesteRequest.fromBuffer(value),
        ($0.RegistrarFeedbackTesteResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetMyTreinamentoRequest,
            $0.MyTreinamentoResponse>(
        'GetMyTreinamento',
        getMyTreinamento_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetMyTreinamentoRequest.fromBuffer(value),
        ($0.MyTreinamentoResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.FinalizarMyTreinamentoRequest,
            $0.SimpleOkResponse>(
        'FinalizarMyTreinamento',
        finalizarMyTreinamento_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.FinalizarMyTreinamentoRequest.fromBuffer(value),
        ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.RemoverMyTreinamentoRequest,
            $0.SimpleOkResponse>(
        'RemoverMyTreinamento',
        removerMyTreinamento_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.RemoverMyTreinamentoRequest.fromBuffer(value),
        ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListMyWhatsappInstancesRequest,
            $0.ListMyWhatsappInstancesResponse>(
        'ListMyWhatsappInstances',
        listMyWhatsappInstances_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListMyWhatsappInstancesRequest.fromBuffer(value),
        ($0.ListMyWhatsappInstancesResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.DefinirRespostaBotInstanciaRequest,
            $0.DefinirRespostaBotInstanciaResponse>(
        'DefinirRespostaBotInstancia',
        definirRespostaBotInstancia_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.DefinirRespostaBotInstanciaRequest.fromBuffer(value),
        ($0.DefinirRespostaBotInstanciaResponse value) =>
            value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.DefinirBotDaConversaRequest,
            $0.DefinirBotDaConversaResponse>(
        'DefinirBotDaConversa',
        definirBotDaConversa_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.DefinirBotDaConversaRequest.fromBuffer(value),
        ($0.DefinirBotDaConversaResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.MarcarAtendimentoLidoRequest,
            $0.MarcarAtendimentoLidoResponse>(
        'MarcarAtendimentoLido',
        marcarAtendimentoLido_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.MarcarAtendimentoLidoRequest.fromBuffer(value),
        ($0.MarcarAtendimentoLidoResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.MyWhatsappInstanceIdRequest,
            $0.SimpleOkResponse>(
        'ReconnectMyWhatsappInstance',
        reconnectMyWhatsappInstance_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.MyWhatsappInstanceIdRequest.fromBuffer(value),
        ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.MyWhatsappInstanceIdRequest,
            $0.SimpleOkResponse>(
        'DeleteMyWhatsappInstance',
        deleteMyWhatsappInstance_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.MyWhatsappInstanceIdRequest.fromBuffer(value),
        ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.MyWhatsappInstanceIdRequest,
            $0.SimpleOkResponse>(
        'DesconectarMyWhatsappInstance',
        desconectarMyWhatsappInstance_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.MyWhatsappInstanceIdRequest.fromBuffer(value),
        ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetVersaoDoAppRequest,
            $0.GetVersaoDoAppResponse>(
        'GetVersaoDoApp',
        getVersaoDoApp_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetVersaoDoAppRequest.fromBuffer(value),
        ($0.GetVersaoDoAppResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.DefinirDepartamentoDaConexaoRequest,
            $0.SimpleOkResponse>(
        'DefinirDepartamentoDaConexao',
        definirDepartamentoDaConexao_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.DefinirDepartamentoDaConexaoRequest.fromBuffer(value),
        ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.DetalheDaConexaoRequest,
            $0.DetalheDaConexaoResponse>(
        'DetalheDaConexao',
        detalheDaConexao_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.DetalheDaConexaoRequest.fromBuffer(value),
        ($0.DetalheDaConexaoResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListMyMensagensNaoEntreguesRequest,
            $0.ListMyMensagensNaoEntreguesResponse>(
        'ListMyMensagensNaoEntregues',
        listMyMensagensNaoEntregues_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListMyMensagensNaoEntreguesRequest.fromBuffer(value),
        ($0.ListMyMensagensNaoEntreguesResponse value) =>
            value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ReenviarMensagemNaoEntregueRequest,
            $0.ReenviarMensagemNaoEntregueResponse>(
        'ReenviarMensagemNaoEntregue',
        reenviarMensagemNaoEntregue_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ReenviarMensagemNaoEntregueRequest.fromBuffer(value),
        ($0.ReenviarMensagemNaoEntregueResponse value) =>
            value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListMyNumerosIgnoradosRequest,
            $0.ListMyNumerosIgnoradosResponse>(
        'ListMyNumerosIgnorados',
        listMyNumerosIgnorados_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListMyNumerosIgnoradosRequest.fromBuffer(value),
        ($0.ListMyNumerosIgnoradosResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CriarNumeroIgnoradoRequest,
            $0.MyNumeroIgnoradoResponse>(
        'CriarNumeroIgnorado',
        criarNumeroIgnorado_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.CriarNumeroIgnoradoRequest.fromBuffer(value),
        ($0.MyNumeroIgnoradoResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.AtualizarNumeroIgnoradoRequest,
            $0.SimpleOkResponse>(
        'AtualizarNumeroIgnorado',
        atualizarNumeroIgnorado_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.AtualizarNumeroIgnoradoRequest.fromBuffer(value),
        ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.NumeroIgnoradoIdRequest, $0.SimpleOkResponse>(
            'RemoverNumeroIgnorado',
            removerNumeroIgnorado_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.NumeroIgnoradoIdRequest.fromBuffer(value),
            ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListMyDepartamentosRequest,
            $0.ListMyDepartamentosResponse>(
        'ListMyDepartamentos',
        listMyDepartamentos_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListMyDepartamentosRequest.fromBuffer(value),
        ($0.ListMyDepartamentosResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.UpdateMyDepartamentoRequest,
            $0.SimpleOkResponse>(
        'UpdateMyDepartamento',
        updateMyDepartamento_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.UpdateMyDepartamentoRequest.fromBuffer(value),
        ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.MyDepartamentoIdRequest, $0.SimpleOkResponse>(
            'DesativarMyDepartamento',
            desativarMyDepartamento_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.MyDepartamentoIdRequest.fromBuffer(value),
            ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListMyAtendentesRequest,
            $0.ListMyAtendentesResponse>(
        'ListMyAtendentes',
        listMyAtendentes_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListMyAtendentesRequest.fromBuffer(value),
        ($0.ListMyAtendentesResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CreateMyAtendenteRequest,
            $0.MyAtendenteResponse>(
        'CreateMyAtendente',
        createMyAtendente_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.CreateMyAtendenteRequest.fromBuffer(value),
        ($0.MyAtendenteResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.UpdateMyAtendenteRequest, $0.SimpleOkResponse>(
            'UpdateMyAtendente',
            updateMyAtendente_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.UpdateMyAtendenteRequest.fromBuffer(value),
            ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.MyAtendenteIdRequest, $0.SimpleOkResponse>(
            'DesativarMyAtendente',
            desativarMyAtendente_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.MyAtendenteIdRequest.fromBuffer(value),
            ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.GetMyPainelRequest, $0.GetMyPainelResponse>(
            'GetMyPainel',
            getMyPainel_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.GetMyPainelRequest.fromBuffer(value),
            ($0.GetMyPainelResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListMyContatosRequest,
            $0.ListMyContatosResponse>(
        'ListMyContatos',
        listMyContatos_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListMyContatosRequest.fromBuffer(value),
        ($0.ListMyContatosResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.CreateMyContatoRequest, $0.MyContatoResponse>(
            'CreateMyContato',
            createMyContato_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.CreateMyContatoRequest.fromBuffer(value),
            ($0.MyContatoResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.UpdateMyContatoRequest, $0.SimpleOkResponse>(
            'UpdateMyContato',
            updateMyContato_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.UpdateMyContatoRequest.fromBuffer(value),
            ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.DefinirMyContatoAtivoRequest,
            $0.SimpleOkResponse>(
        'DefinirMyContatoAtivo',
        definirMyContatoAtivo_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.DefinirMyContatoAtivoRequest.fromBuffer(value),
        ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListMyClientesRequest,
            $0.ListMyClientesResponse>(
        'ListMyClientes',
        listMyClientes_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListMyClientesRequest.fromBuffer(value),
        ($0.ListMyClientesResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.CreateMyClienteRequest, $0.MyClienteResponse>(
            'CreateMyCliente',
            createMyCliente_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.CreateMyClienteRequest.fromBuffer(value),
            ($0.MyClienteResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.UpdateMyClienteRequest, $0.SimpleOkResponse>(
            'UpdateMyCliente',
            updateMyCliente_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.UpdateMyClienteRequest.fromBuffer(value),
            ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.DefinirMyClienteAtivoRequest,
            $0.SimpleOkResponse>(
        'DefinirMyClienteAtivo',
        definirMyClienteAtivo_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.DefinirMyClienteAtivoRequest.fromBuffer(value),
        ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.MyClienteIdRequest,
            $0.ListMyContatosDoClienteResponse>(
        'ListMyContatosDoCliente',
        listMyContatosDoCliente_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.MyClienteIdRequest.fromBuffer(value),
        ($0.ListMyContatosDoClienteResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.VincularMyContatoClienteRequest,
            $0.SimpleOkResponse>(
        'VincularMyContatoCliente',
        vincularMyContatoCliente_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.VincularMyContatoClienteRequest.fromBuffer(value),
        ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.ListMyCamposRequest, $0.ListMyCamposResponse>(
            'ListMyCampos',
            listMyCampos_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ListMyCamposRequest.fromBuffer(value),
            ($0.ListMyCamposResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CreateMyCampoRequest, $0.MyCampoResponse>(
        'CreateMyCampo',
        createMyCampo_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.CreateMyCampoRequest.fromBuffer(value),
        ($0.MyCampoResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.UpdateMyCampoRequest, $0.SimpleOkResponse>(
            'UpdateMyCampo',
            updateMyCampo_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.UpdateMyCampoRequest.fromBuffer(value),
            ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.MyCampoIdRequest, $0.SimpleOkResponse>(
        'DesativarMyCampo',
        desativarMyCampo_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.MyCampoIdRequest.fromBuffer(value),
        ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.SetMyValorCampoRequest, $0.SimpleOkResponse>(
            'SetMyValorCampo',
            setMyValorCampo_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.SetMyValorCampoRequest.fromBuffer(value),
            ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.ListMyFluxosRequest, $0.ListMyFluxosResponse>(
            'ListMyFluxos',
            listMyFluxos_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ListMyFluxosRequest.fromBuffer(value),
            ($0.ListMyFluxosResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CreateMyFluxoRequest, $0.MyFluxoResponse>(
        'CreateMyFluxo',
        createMyFluxo_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.CreateMyFluxoRequest.fromBuffer(value),
        ($0.MyFluxoResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.UpdateMyFluxoRequest, $0.SimpleOkResponse>(
            'UpdateMyFluxo',
            updateMyFluxo_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.UpdateMyFluxoRequest.fromBuffer(value),
            ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.MyFluxoIdRequest, $0.SimpleOkResponse>(
        'DesativarMyFluxo',
        desativarMyFluxo_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.MyFluxoIdRequest.fromBuffer(value),
        ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.MyFluxoIdRequest, $0.ListMyEtapasFluxoResponse>(
            'ListMyEtapasFluxo',
            listMyEtapasFluxo_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.MyFluxoIdRequest.fromBuffer(value),
            ($0.ListMyEtapasFluxoResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CreateMyEtapaFluxoRequest,
            $0.MyEtapaFluxoResponse>(
        'CreateMyEtapaFluxo',
        createMyEtapaFluxo_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.CreateMyEtapaFluxoRequest.fromBuffer(value),
        ($0.MyEtapaFluxoResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.UpdateMyEtapaFluxoRequest, $0.SimpleOkResponse>(
            'UpdateMyEtapaFluxo',
            updateMyEtapaFluxo_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.UpdateMyEtapaFluxoRequest.fromBuffer(value),
            ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.MyEtapaFluxoIdRequest, $0.SimpleOkResponse>(
            'DesativarMyEtapaFluxo',
            desativarMyEtapaFluxo_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.MyEtapaFluxoIdRequest.fromBuffer(value),
            ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.MoverMyEtapaFluxoRequest, $0.SimpleOkResponse>(
            'MoverMyEtapaFluxo',
            moverMyEtapaFluxo_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.MoverMyEtapaFluxoRequest.fromBuffer(value),
            ($0.SimpleOkResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.ListCoreSettingsResponse> listCoreSettings_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListCoreSettingsRequest> $request) async {
    return listCoreSettings($call, await $request);
  }

  $async.Future<$0.ListCoreSettingsResponse> listCoreSettings(
      $grpc.ServiceCall call, $0.ListCoreSettingsRequest request);

  $async.Future<$0.UpsertCoreSettingResponse> upsertCoreSetting_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.UpsertCoreSettingRequest> $request) async {
    return upsertCoreSetting($call, await $request);
  }

  $async.Future<$0.UpsertCoreSettingResponse> upsertCoreSetting(
      $grpc.ServiceCall call, $0.UpsertCoreSettingRequest request);

  $async.Future<$0.DeleteCoreSettingResponse> deleteCoreSetting_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.DeleteCoreSettingRequest> $request) async {
    return deleteCoreSetting($call, await $request);
  }

  $async.Future<$0.DeleteCoreSettingResponse> deleteCoreSetting(
      $grpc.ServiceCall call, $0.DeleteCoreSettingRequest request);

  $async.Future<$0.GetTenantConfigResponse> getTenantConfig_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.GetTenantConfigRequest> $request) async {
    return getTenantConfig($call, await $request);
  }

  $async.Future<$0.GetTenantConfigResponse> getTenantConfig(
      $grpc.ServiceCall call, $0.GetTenantConfigRequest request);

  $async.Future<$0.UpdateTenantConfigResponse> updateTenantConfig_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.UpdateTenantConfigRequest> $request) async {
    return updateTenantConfig($call, await $request);
  }

  $async.Future<$0.UpdateTenantConfigResponse> updateTenantConfig(
      $grpc.ServiceCall call, $0.UpdateTenantConfigRequest request);

  $async.Future<$0.AdminListUsersResponse> adminListUsers_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.AdminListUsersRequest> $request) async {
    return adminListUsers($call, await $request);
  }

  $async.Future<$0.AdminListUsersResponse> adminListUsers(
      $grpc.ServiceCall call, $0.AdminListUsersRequest request);

  $async.Future<$0.AdminSetUserActiveResponse> adminSetUserActive_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.AdminSetUserActiveRequest> $request) async {
    return adminSetUserActive($call, await $request);
  }

  $async.Future<$0.AdminSetUserActiveResponse> adminSetUserActive(
      $grpc.ServiceCall call, $0.AdminSetUserActiveRequest request);

  $async.Future<$0.ListTenantsResponse> listTenants_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ListTenantsRequest> $request) async {
    return listTenants($call, await $request);
  }

  $async.Future<$0.ListTenantsResponse> listTenants(
      $grpc.ServiceCall call, $0.ListTenantsRequest request);

  $async.Future<$0.GetTenantResponse> getTenant_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetTenantRequest> $request) async {
    return getTenant($call, await $request);
  }

  $async.Future<$0.GetTenantResponse> getTenant(
      $grpc.ServiceCall call, $0.GetTenantRequest request);

  $async.Future<$0.CreateTenantResponse> createTenant_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.CreateTenantRequest> $request) async {
    return createTenant($call, await $request);
  }

  $async.Future<$0.CreateTenantResponse> createTenant(
      $grpc.ServiceCall call, $0.CreateTenantRequest request);

  $async.Future<$0.UpdateTenantResponse> updateTenant_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.UpdateTenantRequest> $request) async {
    return updateTenant($call, await $request);
  }

  $async.Future<$0.UpdateTenantResponse> updateTenant(
      $grpc.ServiceCall call, $0.UpdateTenantRequest request);

  $async.Future<$0.SetTenantActiveResponse> setTenantActive_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.SetTenantActiveRequest> $request) async {
    return setTenantActive($call, await $request);
  }

  $async.Future<$0.SetTenantActiveResponse> setTenantActive(
      $grpc.ServiceCall call, $0.SetTenantActiveRequest request);

  $async.Future<$0.GenerateAccessCodeResponse> generateAccessCode_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.GenerateAccessCodeRequest> $request) async {
    return generateAccessCode($call, await $request);
  }

  $async.Future<$0.GenerateAccessCodeResponse> generateAccessCode(
      $grpc.ServiceCall call, $0.GenerateAccessCodeRequest request);

  $async.Future<$0.ListPlansResponse> listPlans_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ListPlansRequest> $request) async {
    return listPlans($call, await $request);
  }

  $async.Future<$0.ListPlansResponse> listPlans(
      $grpc.ServiceCall call, $0.ListPlansRequest request);

  $async.Future<$0.CreatePlanResponse> createPlan_Pre($grpc.ServiceCall $call,
      $async.Future<$0.CreatePlanRequest> $request) async {
    return createPlan($call, await $request);
  }

  $async.Future<$0.CreatePlanResponse> createPlan(
      $grpc.ServiceCall call, $0.CreatePlanRequest request);

  $async.Future<$0.UpdatePlanResponse> updatePlan_Pre($grpc.ServiceCall $call,
      $async.Future<$0.UpdatePlanRequest> $request) async {
    return updatePlan($call, await $request);
  }

  $async.Future<$0.UpdatePlanResponse> updatePlan(
      $grpc.ServiceCall call, $0.UpdatePlanRequest request);

  $async.Future<$0.ListSubscriptionsResponse> listSubscriptions_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListSubscriptionsRequest> $request) async {
    return listSubscriptions($call, await $request);
  }

  $async.Future<$0.ListSubscriptionsResponse> listSubscriptions(
      $grpc.ServiceCall call, $0.ListSubscriptionsRequest request);

  $async.Future<$0.RegisterPaymentResponse> registerPayment_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.RegisterPaymentRequest> $request) async {
    return registerPayment($call, await $request);
  }

  $async.Future<$0.RegisterPaymentResponse> registerPayment(
      $grpc.ServiceCall call, $0.RegisterPaymentRequest request);

  $async.Future<$0.ListPaymentsResponse> listPayments_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListPaymentsRequest> $request) async {
    return listPayments($call, await $request);
  }

  $async.Future<$0.ListPaymentsResponse> listPayments(
      $grpc.ServiceCall call, $0.ListPaymentsRequest request);

  $async.Future<$0.ListVouchersResponse> listVouchers_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListVouchersRequest> $request) async {
    return listVouchers($call, await $request);
  }

  $async.Future<$0.ListVouchersResponse> listVouchers(
      $grpc.ServiceCall call, $0.ListVouchersRequest request);

  $async.Future<$0.CreateVoucherResponse> createVoucher_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.CreateVoucherRequest> $request) async {
    return createVoucher($call, await $request);
  }

  $async.Future<$0.CreateVoucherResponse> createVoucher(
      $grpc.ServiceCall call, $0.CreateVoucherRequest request);

  $async.Future<$0.RevokeVoucherResponse> revokeVoucher_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.RevokeVoucherRequest> $request) async {
    return revokeVoucher($call, await $request);
  }

  $async.Future<$0.RevokeVoucherResponse> revokeVoucher(
      $grpc.ServiceCall call, $0.RevokeVoucherRequest request);

  $async.Future<$0.ListVoucherRedemptionsResponse> listVoucherRedemptions_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListVoucherRedemptionsRequest> $request) async {
    return listVoucherRedemptions($call, await $request);
  }

  $async.Future<$0.ListVoucherRedemptionsResponse> listVoucherRedemptions(
      $grpc.ServiceCall call, $0.ListVoucherRedemptionsRequest request);

  $async.Future<$0.TestEvolutionConnectionResponse> testEvolutionConnection_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.TestEvolutionConnectionRequest> $request) async {
    return testEvolutionConnection($call, await $request);
  }

  $async.Future<$0.TestEvolutionConnectionResponse> testEvolutionConnection(
      $grpc.ServiceCall call, $0.TestEvolutionConnectionRequest request);

  $async.Future<$0.TestarProvedorIaResponse> testarProvedorIa_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.TestarProvedorIaRequest> $request) async {
    return testarProvedorIa($call, await $request);
  }

  $async.Future<$0.TestarProvedorIaResponse> testarProvedorIa(
      $grpc.ServiceCall call, $0.TestarProvedorIaRequest request);

  $async.Future<$0.ListFeatureFlagsResponse> listFeatureFlags_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListFeatureFlagsRequest> $request) async {
    return listFeatureFlags($call, await $request);
  }

  $async.Future<$0.ListFeatureFlagsResponse> listFeatureFlags(
      $grpc.ServiceCall call, $0.ListFeatureFlagsRequest request);

  $async.Future<$0.SetFeatureFlagResponse> setFeatureFlag_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.SetFeatureFlagRequest> $request) async {
    return setFeatureFlag($call, await $request);
  }

  $async.Future<$0.SetFeatureFlagResponse> setFeatureFlag(
      $grpc.ServiceCall call, $0.SetFeatureFlagRequest request);

  $async.Future<$0.SetFeatureFlagOverrideResponse> setFeatureFlagOverride_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.SetFeatureFlagOverrideRequest> $request) async {
    return setFeatureFlagOverride($call, await $request);
  }

  $async.Future<$0.SetFeatureFlagOverrideResponse> setFeatureFlagOverride(
      $grpc.ServiceCall call, $0.SetFeatureFlagOverrideRequest request);

  $async.Future<$0.QueryAuditLogResponse> queryAuditLog_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.QueryAuditLogRequest> $request) async {
    return queryAuditLog($call, await $request);
  }

  $async.Future<$0.QueryAuditLogResponse> queryAuditLog(
      $grpc.ServiceCall call, $0.QueryAuditLogRequest request);

  $async.Future<$0.GetServiceHealthResponse> getServiceHealth_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.GetServiceHealthRequest> $request) async {
    return getServiceHealth($call, await $request);
  }

  $async.Future<$0.GetServiceHealthResponse> getServiceHealth(
      $grpc.ServiceCall call, $0.GetServiceHealthRequest request);

  $async.Future<$0.GetDashboardSummaryResponse> getDashboardSummary_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.GetDashboardSummaryRequest> $request) async {
    return getDashboardSummary($call, await $request);
  }

  $async.Future<$0.GetDashboardSummaryResponse> getDashboardSummary(
      $grpc.ServiceCall call, $0.GetDashboardSummaryRequest request);

  $async.Stream<$0.ExportTenantsCsvResponse> exportTenantsCsv_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ExportTenantsCsvRequest> $request) async* {
    yield* exportTenantsCsv($call, await $request);
  }

  $async.Stream<$0.ExportTenantsCsvResponse> exportTenantsCsv(
      $grpc.ServiceCall call, $0.ExportTenantsCsvRequest request);

  $async.Stream<$0.AtendimentoEvent> streamAtendimentos_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.StreamAtendimentosRequest> $request) async* {
    yield* streamAtendimentos($call, await $request);
  }

  $async.Stream<$0.AtendimentoEvent> streamAtendimentos(
      $grpc.ServiceCall call, $0.StreamAtendimentosRequest request);

  $async.Future<$0.ListAtendimentosResponse> listAtendimentos_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListAtendimentosRequest> $request) async {
    return listAtendimentos($call, await $request);
  }

  $async.Future<$0.ListAtendimentosResponse> listAtendimentos(
      $grpc.ServiceCall call, $0.ListAtendimentosRequest request);

  $async.Future<$0.GetThreadResponse> getThread_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetThreadRequest> $request) async {
    return getThread($call, await $request);
  }

  $async.Future<$0.GetThreadResponse> getThread(
      $grpc.ServiceCall call, $0.GetThreadRequest request);

  $async.Future<$0.IniciarAtendimentoManualResponse>
      iniciarAtendimentoManual_Pre($grpc.ServiceCall $call,
          $async.Future<$0.IniciarAtendimentoManualRequest> $request) async {
    return iniciarAtendimentoManual($call, await $request);
  }

  $async.Future<$0.IniciarAtendimentoManualResponse> iniciarAtendimentoManual(
      $grpc.ServiceCall call, $0.IniciarAtendimentoManualRequest request);

  $async.Future<$0.MoveAtendimentoEtapaResponse> moveAtendimentoEtapa_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.MoveAtendimentoEtapaRequest> $request) async {
    return moveAtendimentoEtapa($call, await $request);
  }

  $async.Future<$0.MoveAtendimentoEtapaResponse> moveAtendimentoEtapa(
      $grpc.ServiceCall call, $0.MoveAtendimentoEtapaRequest request);

  $async.Future<$0.SetAtendimentoStatusResponse> setAtendimentoStatus_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.SetAtendimentoStatusRequest> $request) async {
    return setAtendimentoStatus($call, await $request);
  }

  $async.Future<$0.SetAtendimentoStatusResponse> setAtendimentoStatus(
      $grpc.ServiceCall call, $0.SetAtendimentoStatusRequest request);

  $async.Future<$0.DetalheAtendimentoResponse> getDetalheAtendimento_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.AtendimentoIdRequest> $request) async {
    return getDetalheAtendimento($call, await $request);
  }

  $async.Future<$0.DetalheAtendimentoResponse> getDetalheAtendimento(
      $grpc.ServiceCall call, $0.AtendimentoIdRequest request);

  $async.Future<$0.EtiquetaResponse> createEtiqueta_Pre($grpc.ServiceCall $call,
      $async.Future<$0.CreateEtiquetaRequest> $request) async {
    return createEtiqueta($call, await $request);
  }

  $async.Future<$0.EtiquetaResponse> createEtiqueta(
      $grpc.ServiceCall call, $0.CreateEtiquetaRequest request);

  $async.Future<$0.SimpleOkResponse> alternarEtiqueta_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.AlternarEtiquetaRequest> $request) async {
    return alternarEtiqueta($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> alternarEtiqueta(
      $grpc.ServiceCall call, $0.AlternarEtiquetaRequest request);

  $async.Future<$0.NotaResponse> createNota_Pre($grpc.ServiceCall $call,
      $async.Future<$0.CreateNotaRequest> $request) async {
    return createNota($call, await $request);
  }

  $async.Future<$0.NotaResponse> createNota(
      $grpc.ServiceCall call, $0.CreateNotaRequest request);

  $async.Future<$0.SendOutboundMessageResponse> sendOutboundMessage_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.SendOutboundMessageRequest> $request) async {
    return sendOutboundMessage($call, await $request);
  }

  $async.Future<$0.SendOutboundMessageResponse> sendOutboundMessage(
      $grpc.ServiceCall call, $0.SendOutboundMessageRequest request);

  $async.Future<$0.SolicitarUploadMidiaResponse> solicitarUploadMidia_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.SolicitarUploadMidiaRequest> $request) async {
    return solicitarUploadMidia($call, await $request);
  }

  $async.Future<$0.SolicitarUploadMidiaResponse> solicitarUploadMidia(
      $grpc.ServiceCall call, $0.SolicitarUploadMidiaRequest request);

  $async.Future<$0.EnviarMidiaAtendimentoResponse> enviarMidiaAtendimento_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.EnviarMidiaAtendimentoRequest> $request) async {
    return enviarMidiaAtendimento($call, await $request);
  }

  $async.Future<$0.EnviarMidiaAtendimentoResponse> enviarMidiaAtendimento(
      $grpc.ServiceCall call, $0.EnviarMidiaAtendimentoRequest request);

  $async.Future<$0.ListarMidiasAtendimentoResponse> listarMidiasAtendimento_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListarMidiasAtendimentoRequest> $request) async {
    return listarMidiasAtendimento($call, await $request);
  }

  $async.Future<$0.ListarMidiasAtendimentoResponse> listarMidiasAtendimento(
      $grpc.ServiceCall call, $0.ListarMidiasAtendimentoRequest request);

  $async.Future<$0.EnviarPresencaResponse> enviarPresenca_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.EnviarPresencaRequest> $request) async {
    return enviarPresenca($call, await $request);
  }

  $async.Future<$0.EnviarPresencaResponse> enviarPresenca(
      $grpc.ServiceCall call, $0.EnviarPresencaRequest request);

  $async.Future<$0.ListarTimelineResponse> listarTimelineAtendimento_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListarTimelineRequest> $request) async {
    return listarTimelineAtendimento($call, await $request);
  }

  $async.Future<$0.ListarTimelineResponse> listarTimelineAtendimento(
      $grpc.ServiceCall call, $0.ListarTimelineRequest request);

  $async.Future<$0.ListarAtendimentosDoContatoResponse>
      listarAtendimentosDoContato_Pre($grpc.ServiceCall $call,
          $async.Future<$0.ListarAtendimentosDoContatoRequest> $request) async {
    return listarAtendimentosDoContato($call, await $request);
  }

  $async.Future<$0.ListarAtendimentosDoContatoResponse>
      listarAtendimentosDoContato($grpc.ServiceCall call,
          $0.ListarAtendimentosDoContatoRequest request);

  $async.Future<$0.SimpleOkResponse> removerNota_Pre($grpc.ServiceCall $call,
      $async.Future<$0.RemoverNotaRequest> $request) async {
    return removerNota($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> removerNota(
      $grpc.ServiceCall call, $0.RemoverNotaRequest request);

  $async.Future<$0.EtiquetaResponse> updateEtiqueta_Pre($grpc.ServiceCall $call,
      $async.Future<$0.UpdateEtiquetaRequest> $request) async {
    return updateEtiqueta($call, await $request);
  }

  $async.Future<$0.EtiquetaResponse> updateEtiqueta(
      $grpc.ServiceCall call, $0.UpdateEtiquetaRequest request);

  $async.Future<$0.SimpleOkResponse> desativarEtiqueta_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.DesativarEtiquetaRequest> $request) async {
    return desativarEtiqueta($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> desativarEtiqueta(
      $grpc.ServiceCall call, $0.DesativarEtiquetaRequest request);

  $async.Future<$0.AtribuirAtendimentoResponse> atribuirAtendimento_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.AtribuirAtendimentoRequest> $request) async {
    return atribuirAtendimento($call, await $request);
  }

  $async.Future<$0.AtribuirAtendimentoResponse> atribuirAtendimento(
      $grpc.ServiceCall call, $0.AtribuirAtendimentoRequest request);

  $async.Future<$0.DefinirPrioridadeResponse> definirPrioridade_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.DefinirPrioridadeRequest> $request) async {
    return definirPrioridade($call, await $request);
  }

  $async.Future<$0.DefinirPrioridadeResponse> definirPrioridade(
      $grpc.ServiceCall call, $0.DefinirPrioridadeRequest request);

  $async.Future<$0.TransferirParaFluxoResponse> transferirParaFluxo_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.TransferirParaFluxoRequest> $request) async {
    return transferirParaFluxo($call, await $request);
  }

  $async.Future<$0.TransferirParaFluxoResponse> transferirParaFluxo(
      $grpc.ServiceCall call, $0.TransferirParaFluxoRequest request);

  $async.Future<$0.ExportarQuadroResponse> exportarQuadro_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ExportarQuadroRequest> $request) async {
    return exportarQuadro($call, await $request);
  }

  $async.Future<$0.ExportarQuadroResponse> exportarQuadro(
      $grpc.ServiceCall call, $0.ExportarQuadroRequest request);

  $async.Future<$0.CreateInviteResponse> createInvite_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.CreateInviteRequest> $request) async {
    return createInvite($call, await $request);
  }

  $async.Future<$0.CreateInviteResponse> createInvite(
      $grpc.ServiceCall call, $0.CreateInviteRequest request);

  $async.Future<$0.AcceptInviteResponse> acceptInvite_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.AcceptInviteRequest> $request) async {
    return acceptInvite($call, await $request);
  }

  $async.Future<$0.AcceptInviteResponse> acceptInvite(
      $grpc.ServiceCall call, $0.AcceptInviteRequest request);

  $async.Future<$0.ListInvitesResponse> listInvites_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ListInvitesRequest> $request) async {
    return listInvites($call, await $request);
  }

  $async.Future<$0.ListInvitesResponse> listInvites(
      $grpc.ServiceCall call, $0.ListInvitesRequest request);

  $async.Future<$0.RevokeInviteResponse> revokeInvite_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.RevokeInviteRequest> $request) async {
    return revokeInvite($call, await $request);
  }

  $async.Future<$0.RevokeInviteResponse> revokeInvite(
      $grpc.ServiceCall call, $0.RevokeInviteRequest request);

  $async.Future<$0.ReenviarConviteResponse> reenviarConvite_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ReenviarConviteRequest> $request) async {
    return reenviarConvite($call, await $request);
  }

  $async.Future<$0.ReenviarConviteResponse> reenviarConvite(
      $grpc.ServiceCall call, $0.ReenviarConviteRequest request);

  $async.Future<$0.ListTenantUsersResponse> listTenantUsers_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListTenantUsersRequest> $request) async {
    return listTenantUsers($call, await $request);
  }

  $async.Future<$0.ListTenantUsersResponse> listTenantUsers(
      $grpc.ServiceCall call, $0.ListTenantUsersRequest request);

  $async.Future<$0.UpdateTenantUserResponse> updateTenantUser_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.UpdateTenantUserRequest> $request) async {
    return updateTenantUser($call, await $request);
  }

  $async.Future<$0.UpdateTenantUserResponse> updateTenantUser(
      $grpc.ServiceCall call, $0.UpdateTenantUserRequest request);

  $async.Future<$0.GetTenantConfigResponse> getMyTenantConfig_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.GetMyTenantConfigRequest> $request) async {
    return getMyTenantConfig($call, await $request);
  }

  $async.Future<$0.GetTenantConfigResponse> getMyTenantConfig(
      $grpc.ServiceCall call, $0.GetMyTenantConfigRequest request);

  $async.Future<$0.UpdateTenantConfigResponse> updateMyTenantConfig_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.UpdateMyTenantConfigRequest> $request) async {
    return updateMyTenantConfig($call, await $request);
  }

  $async.Future<$0.UpdateTenantConfigResponse> updateMyTenantConfig(
      $grpc.ServiceCall call, $0.UpdateMyTenantConfigRequest request);

  $async.Future<$0.ListMcpGrantsResponse> listMcpGrants_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListMcpGrantsRequest> $request) async {
    return listMcpGrants($call, await $request);
  }

  $async.Future<$0.ListMcpGrantsResponse> listMcpGrants(
      $grpc.ServiceCall call, $0.ListMcpGrantsRequest request);

  $async.Future<$0.RevokeMcpGrantResponse> revokeMcpGrant_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.RevokeMcpGrantRequest> $request) async {
    return revokeMcpGrant($call, await $request);
  }

  $async.Future<$0.RevokeMcpGrantResponse> revokeMcpGrant(
      $grpc.ServiceCall call, $0.RevokeMcpGrantRequest request);

  $async.Future<$0.AjustarEscoposMcpGrantResponse> ajustarEscoposMcpGrant_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.AjustarEscoposMcpGrantRequest> $request) async {
    return ajustarEscoposMcpGrant($call, await $request);
  }

  $async.Future<$0.AjustarEscoposMcpGrantResponse> ajustarEscoposMcpGrant(
      $grpc.ServiceCall call, $0.AjustarEscoposMcpGrantRequest request);

  $async.Future<$0.ListMyAuditLogResponse> listMyAuditLog_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListMyAuditLogRequest> $request) async {
    return listMyAuditLog($call, await $request);
  }

  $async.Future<$0.ListMyAuditLogResponse> listMyAuditLog(
      $grpc.ServiceCall call, $0.ListMyAuditLogRequest request);

  $async.Future<$0.CreateMyWhatsappInstanceResponse>
      createMyWhatsappInstance_Pre($grpc.ServiceCall $call,
          $async.Future<$0.CreateMyWhatsappInstanceRequest> $request) async {
    return createMyWhatsappInstance($call, await $request);
  }

  $async.Future<$0.CreateMyWhatsappInstanceResponse> createMyWhatsappInstance(
      $grpc.ServiceCall call, $0.CreateMyWhatsappInstanceRequest request);

  $async.Future<$0.GetMyWhatsappInstanceStatusResponse>
      getMyWhatsappInstanceStatus_Pre($grpc.ServiceCall $call,
          $async.Future<$0.GetMyWhatsappInstanceStatusRequest> $request) async {
    return getMyWhatsappInstanceStatus($call, await $request);
  }

  $async.Future<$0.GetMyWhatsappInstanceStatusResponse>
      getMyWhatsappInstanceStatus($grpc.ServiceCall call,
          $0.GetMyWhatsappInstanceStatusRequest request);

  $async.Future<$0.CreateMyDepartamentoResponse> createMyDepartamento_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.CreateMyDepartamentoRequest> $request) async {
    return createMyDepartamento($call, await $request);
  }

  $async.Future<$0.CreateMyDepartamentoResponse> createMyDepartamento(
      $grpc.ServiceCall call, $0.CreateMyDepartamentoRequest request);

  $async.Future<$0.SetMyBotPersonaResponse> setMyBotPersona_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.SetMyBotPersonaRequest> $request) async {
    return setMyBotPersona($call, await $request);
  }

  $async.Future<$0.SetMyBotPersonaResponse> setMyBotPersona(
      $grpc.ServiceCall call, $0.SetMyBotPersonaRequest request);

  $async.Future<$0.SetOnboardingProgressResponse> setOnboardingProgress_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.SetOnboardingProgressRequest> $request) async {
    return setOnboardingProgress($call, await $request);
  }

  $async.Future<$0.SetOnboardingProgressResponse> setOnboardingProgress(
      $grpc.ServiceCall call, $0.SetOnboardingProgressRequest request);

  $async.Future<$0.GetMyOnboardingProgressResponse> getMyOnboardingProgress_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.GetMyOnboardingProgressRequest> $request) async {
    return getMyOnboardingProgress($call, await $request);
  }

  $async.Future<$0.GetMyOnboardingProgressResponse> getMyOnboardingProgress(
      $grpc.ServiceCall call, $0.GetMyOnboardingProgressRequest request);

  $async.Future<$0.QuitarMinhaAssinaturaResponse> quitarMinhaAssinatura_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.QuitarMinhaAssinaturaRequest> $request) async {
    return quitarMinhaAssinatura($call, await $request);
  }

  $async.Future<$0.QuitarMinhaAssinaturaResponse> quitarMinhaAssinatura(
      $grpc.ServiceCall call, $0.QuitarMinhaAssinaturaRequest request);

  $async.Future<$0.MyTreinamentoResponse> createMyTreinamento_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.CreateMyTreinamentoRequest> $request) async {
    return createMyTreinamento($call, await $request);
  }

  $async.Future<$0.MyTreinamentoResponse> createMyTreinamento(
      $grpc.ServiceCall call, $0.CreateMyTreinamentoRequest request);

  $async.Future<$0.ListMyTreinamentosResponse> listMyTreinamentos_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListMyTreinamentosRequest> $request) async {
    return listMyTreinamentos($call, await $request);
  }

  $async.Future<$0.ListMyTreinamentosResponse> listMyTreinamentos(
      $grpc.ServiceCall call, $0.ListMyTreinamentosRequest request);

  $async.Future<$0.ListMyIntentsResponse> listMyIntents_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListMyIntentsRequest> $request) async {
    return listMyIntents($call, await $request);
  }

  $async.Future<$0.ListMyIntentsResponse> listMyIntents(
      $grpc.ServiceCall call, $0.ListMyIntentsRequest request);

  $async.Future<$0.MyIntentResponse> createMyIntent_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.MyIntentDados> $request) async {
    return createMyIntent($call, await $request);
  }

  $async.Future<$0.MyIntentResponse> createMyIntent(
      $grpc.ServiceCall call, $0.MyIntentDados request);

  $async.Future<$0.SimpleOkResponse> updateMyIntent_Pre($grpc.ServiceCall $call,
      $async.Future<$0.UpdateMyIntentRequest> $request) async {
    return updateMyIntent($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> updateMyIntent(
      $grpc.ServiceCall call, $0.UpdateMyIntentRequest request);

  $async.Future<$0.SimpleOkResponse> removeMyIntent_Pre($grpc.ServiceCall $call,
      $async.Future<$0.MyIntentIdRequest> $request) async {
    return removeMyIntent($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> removeMyIntent(
      $grpc.ServiceCall call, $0.MyIntentIdRequest request);

  $async.Future<$0.TestarPerguntaResponse> testarPergunta_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.TestarPerguntaRequest> $request) async {
    return testarPergunta($call, await $request);
  }

  $async.Future<$0.TestarPerguntaResponse> testarPergunta(
      $grpc.ServiceCall call, $0.TestarPerguntaRequest request);

  $async.Future<$0.SolicitarUploadTreinamentoResponse>
      solicitarUploadTreinamento_Pre($grpc.ServiceCall $call,
          $async.Future<$0.SolicitarUploadTreinamentoRequest> $request) async {
    return solicitarUploadTreinamento($call, await $request);
  }

  $async.Future<$0.SolicitarUploadTreinamentoResponse>
      solicitarUploadTreinamento(
          $grpc.ServiceCall call, $0.SolicitarUploadTreinamentoRequest request);

  $async.Future<$0.MyTreinamentoResponse> createMyTreinamentoComArquivo_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.CreateMyTreinamentoComArquivoRequest> $request) async {
    return createMyTreinamentoComArquivo($call, await $request);
  }

  $async.Future<$0.MyTreinamentoResponse> createMyTreinamentoComArquivo(
      $grpc.ServiceCall call, $0.CreateMyTreinamentoComArquivoRequest request);

  $async.Future<$0.RegistrarFeedbackTesteResponse> registrarFeedbackTeste_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.RegistrarFeedbackTesteRequest> $request) async {
    return registrarFeedbackTeste($call, await $request);
  }

  $async.Future<$0.RegistrarFeedbackTesteResponse> registrarFeedbackTeste(
      $grpc.ServiceCall call, $0.RegistrarFeedbackTesteRequest request);

  $async.Future<$0.MyTreinamentoResponse> getMyTreinamento_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.GetMyTreinamentoRequest> $request) async {
    return getMyTreinamento($call, await $request);
  }

  $async.Future<$0.MyTreinamentoResponse> getMyTreinamento(
      $grpc.ServiceCall call, $0.GetMyTreinamentoRequest request);

  $async.Future<$0.SimpleOkResponse> finalizarMyTreinamento_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.FinalizarMyTreinamentoRequest> $request) async {
    return finalizarMyTreinamento($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> finalizarMyTreinamento(
      $grpc.ServiceCall call, $0.FinalizarMyTreinamentoRequest request);

  $async.Future<$0.SimpleOkResponse> removerMyTreinamento_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.RemoverMyTreinamentoRequest> $request) async {
    return removerMyTreinamento($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> removerMyTreinamento(
      $grpc.ServiceCall call, $0.RemoverMyTreinamentoRequest request);

  $async.Future<$0.ListMyWhatsappInstancesResponse> listMyWhatsappInstances_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListMyWhatsappInstancesRequest> $request) async {
    return listMyWhatsappInstances($call, await $request);
  }

  $async.Future<$0.ListMyWhatsappInstancesResponse> listMyWhatsappInstances(
      $grpc.ServiceCall call, $0.ListMyWhatsappInstancesRequest request);

  $async.Future<$0.DefinirRespostaBotInstanciaResponse>
      definirRespostaBotInstancia_Pre($grpc.ServiceCall $call,
          $async.Future<$0.DefinirRespostaBotInstanciaRequest> $request) async {
    return definirRespostaBotInstancia($call, await $request);
  }

  $async.Future<$0.DefinirRespostaBotInstanciaResponse>
      definirRespostaBotInstancia($grpc.ServiceCall call,
          $0.DefinirRespostaBotInstanciaRequest request);

  $async.Future<$0.DefinirBotDaConversaResponse> definirBotDaConversa_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.DefinirBotDaConversaRequest> $request) async {
    return definirBotDaConversa($call, await $request);
  }

  $async.Future<$0.DefinirBotDaConversaResponse> definirBotDaConversa(
      $grpc.ServiceCall call, $0.DefinirBotDaConversaRequest request);

  $async.Future<$0.MarcarAtendimentoLidoResponse> marcarAtendimentoLido_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.MarcarAtendimentoLidoRequest> $request) async {
    return marcarAtendimentoLido($call, await $request);
  }

  $async.Future<$0.MarcarAtendimentoLidoResponse> marcarAtendimentoLido(
      $grpc.ServiceCall call, $0.MarcarAtendimentoLidoRequest request);

  $async.Future<$0.SimpleOkResponse> reconnectMyWhatsappInstance_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.MyWhatsappInstanceIdRequest> $request) async {
    return reconnectMyWhatsappInstance($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> reconnectMyWhatsappInstance(
      $grpc.ServiceCall call, $0.MyWhatsappInstanceIdRequest request);

  $async.Future<$0.SimpleOkResponse> deleteMyWhatsappInstance_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.MyWhatsappInstanceIdRequest> $request) async {
    return deleteMyWhatsappInstance($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> deleteMyWhatsappInstance(
      $grpc.ServiceCall call, $0.MyWhatsappInstanceIdRequest request);

  $async.Future<$0.SimpleOkResponse> desconectarMyWhatsappInstance_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.MyWhatsappInstanceIdRequest> $request) async {
    return desconectarMyWhatsappInstance($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> desconectarMyWhatsappInstance(
      $grpc.ServiceCall call, $0.MyWhatsappInstanceIdRequest request);

  $async.Future<$0.GetVersaoDoAppResponse> getVersaoDoApp_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.GetVersaoDoAppRequest> $request) async {
    return getVersaoDoApp($call, await $request);
  }

  $async.Future<$0.GetVersaoDoAppResponse> getVersaoDoApp(
      $grpc.ServiceCall call, $0.GetVersaoDoAppRequest request);

  $async.Future<$0.SimpleOkResponse> definirDepartamentoDaConexao_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.DefinirDepartamentoDaConexaoRequest> $request) async {
    return definirDepartamentoDaConexao($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> definirDepartamentoDaConexao(
      $grpc.ServiceCall call, $0.DefinirDepartamentoDaConexaoRequest request);

  $async.Future<$0.DetalheDaConexaoResponse> detalheDaConexao_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.DetalheDaConexaoRequest> $request) async {
    return detalheDaConexao($call, await $request);
  }

  $async.Future<$0.DetalheDaConexaoResponse> detalheDaConexao(
      $grpc.ServiceCall call, $0.DetalheDaConexaoRequest request);

  $async.Future<$0.ListMyMensagensNaoEntreguesResponse>
      listMyMensagensNaoEntregues_Pre($grpc.ServiceCall $call,
          $async.Future<$0.ListMyMensagensNaoEntreguesRequest> $request) async {
    return listMyMensagensNaoEntregues($call, await $request);
  }

  $async.Future<$0.ListMyMensagensNaoEntreguesResponse>
      listMyMensagensNaoEntregues($grpc.ServiceCall call,
          $0.ListMyMensagensNaoEntreguesRequest request);

  $async.Future<$0.ReenviarMensagemNaoEntregueResponse>
      reenviarMensagemNaoEntregue_Pre($grpc.ServiceCall $call,
          $async.Future<$0.ReenviarMensagemNaoEntregueRequest> $request) async {
    return reenviarMensagemNaoEntregue($call, await $request);
  }

  $async.Future<$0.ReenviarMensagemNaoEntregueResponse>
      reenviarMensagemNaoEntregue($grpc.ServiceCall call,
          $0.ReenviarMensagemNaoEntregueRequest request);

  $async.Future<$0.ListMyNumerosIgnoradosResponse> listMyNumerosIgnorados_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListMyNumerosIgnoradosRequest> $request) async {
    return listMyNumerosIgnorados($call, await $request);
  }

  $async.Future<$0.ListMyNumerosIgnoradosResponse> listMyNumerosIgnorados(
      $grpc.ServiceCall call, $0.ListMyNumerosIgnoradosRequest request);

  $async.Future<$0.MyNumeroIgnoradoResponse> criarNumeroIgnorado_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.CriarNumeroIgnoradoRequest> $request) async {
    return criarNumeroIgnorado($call, await $request);
  }

  $async.Future<$0.MyNumeroIgnoradoResponse> criarNumeroIgnorado(
      $grpc.ServiceCall call, $0.CriarNumeroIgnoradoRequest request);

  $async.Future<$0.SimpleOkResponse> atualizarNumeroIgnorado_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.AtualizarNumeroIgnoradoRequest> $request) async {
    return atualizarNumeroIgnorado($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> atualizarNumeroIgnorado(
      $grpc.ServiceCall call, $0.AtualizarNumeroIgnoradoRequest request);

  $async.Future<$0.SimpleOkResponse> removerNumeroIgnorado_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.NumeroIgnoradoIdRequest> $request) async {
    return removerNumeroIgnorado($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> removerNumeroIgnorado(
      $grpc.ServiceCall call, $0.NumeroIgnoradoIdRequest request);

  $async.Future<$0.ListMyDepartamentosResponse> listMyDepartamentos_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListMyDepartamentosRequest> $request) async {
    return listMyDepartamentos($call, await $request);
  }

  $async.Future<$0.ListMyDepartamentosResponse> listMyDepartamentos(
      $grpc.ServiceCall call, $0.ListMyDepartamentosRequest request);

  $async.Future<$0.SimpleOkResponse> updateMyDepartamento_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.UpdateMyDepartamentoRequest> $request) async {
    return updateMyDepartamento($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> updateMyDepartamento(
      $grpc.ServiceCall call, $0.UpdateMyDepartamentoRequest request);

  $async.Future<$0.SimpleOkResponse> desativarMyDepartamento_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.MyDepartamentoIdRequest> $request) async {
    return desativarMyDepartamento($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> desativarMyDepartamento(
      $grpc.ServiceCall call, $0.MyDepartamentoIdRequest request);

  $async.Future<$0.ListMyAtendentesResponse> listMyAtendentes_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListMyAtendentesRequest> $request) async {
    return listMyAtendentes($call, await $request);
  }

  $async.Future<$0.ListMyAtendentesResponse> listMyAtendentes(
      $grpc.ServiceCall call, $0.ListMyAtendentesRequest request);

  $async.Future<$0.MyAtendenteResponse> createMyAtendente_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.CreateMyAtendenteRequest> $request) async {
    return createMyAtendente($call, await $request);
  }

  $async.Future<$0.MyAtendenteResponse> createMyAtendente(
      $grpc.ServiceCall call, $0.CreateMyAtendenteRequest request);

  $async.Future<$0.SimpleOkResponse> updateMyAtendente_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.UpdateMyAtendenteRequest> $request) async {
    return updateMyAtendente($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> updateMyAtendente(
      $grpc.ServiceCall call, $0.UpdateMyAtendenteRequest request);

  $async.Future<$0.SimpleOkResponse> desativarMyAtendente_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.MyAtendenteIdRequest> $request) async {
    return desativarMyAtendente($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> desativarMyAtendente(
      $grpc.ServiceCall call, $0.MyAtendenteIdRequest request);

  $async.Future<$0.GetMyPainelResponse> getMyPainel_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetMyPainelRequest> $request) async {
    return getMyPainel($call, await $request);
  }

  $async.Future<$0.GetMyPainelResponse> getMyPainel(
      $grpc.ServiceCall call, $0.GetMyPainelRequest request);

  $async.Future<$0.ListMyContatosResponse> listMyContatos_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListMyContatosRequest> $request) async {
    return listMyContatos($call, await $request);
  }

  $async.Future<$0.ListMyContatosResponse> listMyContatos(
      $grpc.ServiceCall call, $0.ListMyContatosRequest request);

  $async.Future<$0.MyContatoResponse> createMyContato_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.CreateMyContatoRequest> $request) async {
    return createMyContato($call, await $request);
  }

  $async.Future<$0.MyContatoResponse> createMyContato(
      $grpc.ServiceCall call, $0.CreateMyContatoRequest request);

  $async.Future<$0.SimpleOkResponse> updateMyContato_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.UpdateMyContatoRequest> $request) async {
    return updateMyContato($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> updateMyContato(
      $grpc.ServiceCall call, $0.UpdateMyContatoRequest request);

  $async.Future<$0.SimpleOkResponse> definirMyContatoAtivo_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.DefinirMyContatoAtivoRequest> $request) async {
    return definirMyContatoAtivo($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> definirMyContatoAtivo(
      $grpc.ServiceCall call, $0.DefinirMyContatoAtivoRequest request);

  $async.Future<$0.ListMyClientesResponse> listMyClientes_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListMyClientesRequest> $request) async {
    return listMyClientes($call, await $request);
  }

  $async.Future<$0.ListMyClientesResponse> listMyClientes(
      $grpc.ServiceCall call, $0.ListMyClientesRequest request);

  $async.Future<$0.MyClienteResponse> createMyCliente_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.CreateMyClienteRequest> $request) async {
    return createMyCliente($call, await $request);
  }

  $async.Future<$0.MyClienteResponse> createMyCliente(
      $grpc.ServiceCall call, $0.CreateMyClienteRequest request);

  $async.Future<$0.SimpleOkResponse> updateMyCliente_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.UpdateMyClienteRequest> $request) async {
    return updateMyCliente($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> updateMyCliente(
      $grpc.ServiceCall call, $0.UpdateMyClienteRequest request);

  $async.Future<$0.SimpleOkResponse> definirMyClienteAtivo_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.DefinirMyClienteAtivoRequest> $request) async {
    return definirMyClienteAtivo($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> definirMyClienteAtivo(
      $grpc.ServiceCall call, $0.DefinirMyClienteAtivoRequest request);

  $async.Future<$0.ListMyContatosDoClienteResponse> listMyContatosDoCliente_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.MyClienteIdRequest> $request) async {
    return listMyContatosDoCliente($call, await $request);
  }

  $async.Future<$0.ListMyContatosDoClienteResponse> listMyContatosDoCliente(
      $grpc.ServiceCall call, $0.MyClienteIdRequest request);

  $async.Future<$0.SimpleOkResponse> vincularMyContatoCliente_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.VincularMyContatoClienteRequest> $request) async {
    return vincularMyContatoCliente($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> vincularMyContatoCliente(
      $grpc.ServiceCall call, $0.VincularMyContatoClienteRequest request);

  $async.Future<$0.ListMyCamposResponse> listMyCampos_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListMyCamposRequest> $request) async {
    return listMyCampos($call, await $request);
  }

  $async.Future<$0.ListMyCamposResponse> listMyCampos(
      $grpc.ServiceCall call, $0.ListMyCamposRequest request);

  $async.Future<$0.MyCampoResponse> createMyCampo_Pre($grpc.ServiceCall $call,
      $async.Future<$0.CreateMyCampoRequest> $request) async {
    return createMyCampo($call, await $request);
  }

  $async.Future<$0.MyCampoResponse> createMyCampo(
      $grpc.ServiceCall call, $0.CreateMyCampoRequest request);

  $async.Future<$0.SimpleOkResponse> updateMyCampo_Pre($grpc.ServiceCall $call,
      $async.Future<$0.UpdateMyCampoRequest> $request) async {
    return updateMyCampo($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> updateMyCampo(
      $grpc.ServiceCall call, $0.UpdateMyCampoRequest request);

  $async.Future<$0.SimpleOkResponse> desativarMyCampo_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.MyCampoIdRequest> $request) async {
    return desativarMyCampo($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> desativarMyCampo(
      $grpc.ServiceCall call, $0.MyCampoIdRequest request);

  $async.Future<$0.SimpleOkResponse> setMyValorCampo_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.SetMyValorCampoRequest> $request) async {
    return setMyValorCampo($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> setMyValorCampo(
      $grpc.ServiceCall call, $0.SetMyValorCampoRequest request);

  $async.Future<$0.ListMyFluxosResponse> listMyFluxos_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListMyFluxosRequest> $request) async {
    return listMyFluxos($call, await $request);
  }

  $async.Future<$0.ListMyFluxosResponse> listMyFluxos(
      $grpc.ServiceCall call, $0.ListMyFluxosRequest request);

  $async.Future<$0.MyFluxoResponse> createMyFluxo_Pre($grpc.ServiceCall $call,
      $async.Future<$0.CreateMyFluxoRequest> $request) async {
    return createMyFluxo($call, await $request);
  }

  $async.Future<$0.MyFluxoResponse> createMyFluxo(
      $grpc.ServiceCall call, $0.CreateMyFluxoRequest request);

  $async.Future<$0.SimpleOkResponse> updateMyFluxo_Pre($grpc.ServiceCall $call,
      $async.Future<$0.UpdateMyFluxoRequest> $request) async {
    return updateMyFluxo($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> updateMyFluxo(
      $grpc.ServiceCall call, $0.UpdateMyFluxoRequest request);

  $async.Future<$0.SimpleOkResponse> desativarMyFluxo_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.MyFluxoIdRequest> $request) async {
    return desativarMyFluxo($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> desativarMyFluxo(
      $grpc.ServiceCall call, $0.MyFluxoIdRequest request);

  $async.Future<$0.ListMyEtapasFluxoResponse> listMyEtapasFluxo_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.MyFluxoIdRequest> $request) async {
    return listMyEtapasFluxo($call, await $request);
  }

  $async.Future<$0.ListMyEtapasFluxoResponse> listMyEtapasFluxo(
      $grpc.ServiceCall call, $0.MyFluxoIdRequest request);

  $async.Future<$0.MyEtapaFluxoResponse> createMyEtapaFluxo_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.CreateMyEtapaFluxoRequest> $request) async {
    return createMyEtapaFluxo($call, await $request);
  }

  $async.Future<$0.MyEtapaFluxoResponse> createMyEtapaFluxo(
      $grpc.ServiceCall call, $0.CreateMyEtapaFluxoRequest request);

  $async.Future<$0.SimpleOkResponse> updateMyEtapaFluxo_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.UpdateMyEtapaFluxoRequest> $request) async {
    return updateMyEtapaFluxo($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> updateMyEtapaFluxo(
      $grpc.ServiceCall call, $0.UpdateMyEtapaFluxoRequest request);

  $async.Future<$0.SimpleOkResponse> desativarMyEtapaFluxo_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.MyEtapaFluxoIdRequest> $request) async {
    return desativarMyEtapaFluxo($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> desativarMyEtapaFluxo(
      $grpc.ServiceCall call, $0.MyEtapaFluxoIdRequest request);

  $async.Future<$0.SimpleOkResponse> moverMyEtapaFluxo_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.MoverMyEtapaFluxoRequest> $request) async {
    return moverMyEtapaFluxo($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> moverMyEtapaFluxo(
      $grpc.ServiceCall call, $0.MoverMyEtapaFluxoRequest request);
}
