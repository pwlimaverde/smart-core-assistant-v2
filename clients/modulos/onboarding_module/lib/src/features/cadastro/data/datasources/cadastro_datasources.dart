import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/cadastro_models.dart';
import '../../domain/parameters/cadastro_parameters.dart';

/// Datasources do wizard: **só I/O** e a tradução protobuf → modelo de domínio.
///
/// Sem `try/catch` em lugar nenhum — o datasource é burro e deixa a exceção
/// técnica subir com todo o contexto para o `mapError` do repositório. É o único
/// arquivo do módulo que conhece os stubs gerados.

/// Traduz o enum do proto para o do domínio. Um modo desconhecido (proto novo,
/// cliente antigo) cai em `assincrona`: a tela então espera confirmação em vez
/// de assumir que já pagou.
ModoConfirmacaoPagamento _modoDoProto(ModoConfirmacao modo) =>
    switch (modo) {
      ModoConfirmacao.MODO_CONFIRMACAO_IMEDIATA =>
        ModoConfirmacaoPagamento.imediata,
      _ => ModoConfirmacaoPagamento.assincrona,
    };

final class VerificarSlugDatasource
    implements Datasource<SlugDisponibilidade, SlugParameters> {
  final OnboardingServiceClient _client;

  const VerificarSlugDatasource({required this._client});

  @override
  Future<SlugDisponibilidade> call(SlugParameters parameters) async {
    final resp = await _client.checkSlug(
      CheckSlugRequest(slug: parameters.slug),
    );
    return SlugDisponibilidade(
      disponivel: resp.disponivel,
      mensagem: resp.mensagem,
    );
  }
}

final class ListarPlanosDatasource
    implements Datasource<List<PlanoPublico>, SemParametros> {
  final OnboardingServiceClient _client;

  const ListarPlanosDatasource({required this._client});

  @override
  Future<List<PlanoPublico>> call(SemParametros parameters) async {
    final resp = await _client.listPublicPlans(ListPublicPlansRequest());
    return resp.planos
        .map(
          (p) => PlanoPublico(
            id: p.id,
            nome: p.name,
            descricao: p.description,
            preco: p.price,
            maxInstancias: p.maxInstances,
            maxDepartamentos: p.maxDepartments,
            maxFluxos: p.maxFluxos,
          ),
        )
        .toList(growable: false);
  }
}

final class ListarProvedoresDatasource
    implements Datasource<List<ProvedorPagamento>, SemParametros> {
  final OnboardingServiceClient _client;

  const ListarProvedoresDatasource({required this._client});

  @override
  Future<List<ProvedorPagamento>> call(SemParametros parameters) async {
    final resp = await _client.listPaymentProviders(
      ListPaymentProvidersRequest(),
    );
    return resp.provedores
        .map(
          (p) => ProvedorPagamento(
            id: p.id,
            rotulo: p.rotulo,
            instrucao: p.instrucao,
            requerCredencial: p.requerCredencial,
            rotuloCredencial: p.rotuloCredencial,
            modo: _modoDoProto(p.modo),
          ),
        )
        .toList(growable: false);
  }
}

final class IniciarCadastroDatasource
    implements Datasource<CadastroIniciado, IniciarCadastroParameters> {
  final OnboardingServiceClient _client;

  const IniciarCadastroDatasource({required this._client});

  @override
  Future<CadastroIniciado> call(IniciarCadastroParameters parameters) async {
    final resp = await _client.startSignup(
      StartSignupRequest(
        name: parameters.nome,
        slug: parameters.slug,
        email: parameters.email,
        password: parameters.senha,
        phone: parameters.telefone,
      ),
    );
    return CadastroIniciado(
      tenantId: resp.tenantId,
      signupToken: resp.signupToken,
      proximoPasso: resp.proximoPasso,
    );
  }
}

final class SelecionarPlanoDatasource
    implements Datasource<int, SelecionarPlanoParameters> {
  final OnboardingServiceClient _client;

  const SelecionarPlanoDatasource({required this._client});

  @override
  Future<int> call(SelecionarPlanoParameters parameters) async {
    final resp = await _client.selectPlan(
      SelectPlanRequest(
        tenantId: parameters.tenantId,
        signupToken: parameters.signupToken,
        planId: parameters.planoId,
      ),
    );
    return resp.proximoPasso;
  }
}

final class ConfirmarPagamentoDatasource
    implements Datasource<ResultadoPagamento, ConfirmarPagamentoParameters> {
  final OnboardingServiceClient _client;

  const ConfirmarPagamentoDatasource({required this._client});

  @override
  Future<ResultadoPagamento> call(
    ConfirmarPagamentoParameters parameters,
  ) async {
    final resp = await _client.confirmPayment(
      ConfirmPaymentRequest(
        tenantId: parameters.tenantId,
        signupToken: parameters.signupToken,
        provedor: parameters.provedorId,
        credencial: parameters.credencial,
      ),
    );
    return ResultadoPagamento(
      confirmado: resp.confirmado,
      urlRedirecionamento: resp.urlRedirecionamento,
      mensagem: resp.mensagem,
    );
  }
}

final class StatusCadastroDatasource
    implements Datasource<StatusCadastro, StatusCadastroParameters> {
  final OnboardingServiceClient _client;

  const StatusCadastroDatasource({required this._client});

  @override
  Future<StatusCadastro> call(StatusCadastroParameters parameters) async {
    final resp = await _client.getSignupStatus(
      GetSignupStatusRequest(
        tenantId: parameters.tenantId,
        signupToken: parameters.signupToken,
      ),
    );
    return StatusCadastro(
      passo: resp.passo,
      planoId: resp.planId,
      statusAssinatura: resp.statusAssinatura,
      tenantAtivo: resp.tenantAtivo,
    );
  }
}
