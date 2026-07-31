import 'package:dependencies_module/dependencies_module.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/model/cadastro_models.dart';
import '../../domain/services/cadastro_sessao.dart';
import '../controllers/cadastro_controllers.dart';
import '../widgets/cadastro_shell.dart';

/// Passo 3 — pagamento.
///
/// A tela **não conhece nenhum provedor por nome**: desenha o que o servidor
/// declarar em `ListPaymentProviders`. Hoje isso é só o voucher; quando um
/// gateway entrar, ele aparece aqui sem uma linha de código nova — inclusive o
/// caminho de sair para pagar fora do app, que já está implementado abaixo.
final class CadastroPagamentoPage extends StatefulWidget {
  const CadastroPagamentoPage({super.key});

  @override
  State<CadastroPagamentoPage> createState() => _CadastroPagamentoPageState();
}

class _CadastroPagamentoPageState extends State<CadastroPagamentoPage> {
  late final PagamentoController _controller;
  final _credencial = TextEditingController();

  String? _provedorSelecionado;
  bool _confirmando = false;

  /// Mensagem de recusa vinda do servidor (código expirado, revogado...). É
  /// distinta de um erro de sistema, e aparece junto ao campo.
  String? _recusa;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _controller = inject<PagamentoController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sessao = inject<CadastroSessao>();
      if (!sessao.iniciado) {
        if (mounted) context.go('/cadastro');
        return;
      }
      if (!sessao.temPlano) {
        if (mounted) context.go('/cadastro/plano');
        return;
      }
      _controller.carregar();
    });
  }

  @override
  void dispose() {
    _credencial.dispose();
    super.dispose();
  }

  Future<void> _confirmar(ProvedorPagamento provedor) async {
    setState(() {
      _confirmando = true;
      _recusa = null;
      _erro = null;
    });

    final res = await _controller.confirmar(
      provedorId: provedor.id,
      credencial: _credencial.text.trim(),
    );
    if (!mounted) return;

    switch (res) {
      case Success(:final value) when value.confirmado:
        context.go('/cadastro/pronto');
      case Success(:final value) when value.exigeRedirecionamento:
        // Caminho do gateway: o usuário conclui fora e a confirmação chega
        // depois, por webhook. A tela de conclusão fica consultando o estado.
        await _abrir(value.urlRedirecionamento);
        if (mounted) context.go('/cadastro/pronto');
      case Success(:final value):
        setState(() {
          _confirmando = false;
          _recusa = value.mensagem;
        });
      case Failure(:final error):
        setState(() {
          _confirmando = false;
          _erro = ErrorMessageMapper.map(error);
        });
    }
  }

  Future<void> _abrir(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return CadastroShell(
      passo: 3,
      titulo: 'Pagamento',
      subtitulo: 'Confirme o pagamento para liberar o acesso.',
      aoVoltar: () => context.go('/cadastro/plano'),
      child: BlocBuilder<PagamentoController, ViewState<List<ProvedorPagamento>>>(
        bloc: _controller,
        builder: (context, state) => switch (state) {
          InitialState() || LoadingState() => const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
          ErrorState(:final error) => Column(
              children: [
                CadastroErrorBanner(message: ErrorMessageMapper.map(error)),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  label: 'Tentar de novo',
                  onPressed: _controller.carregar,
                ),
              ],
            ),
          SuccessState(:final data) => _Formas(
              provedores: data,
              selecionado: _provedorSelecionado ??
                  (data.length == 1 ? data.first.id : null),
              credencial: _credencial,
              recusa: _recusa,
              erro: _erro,
              confirmando: _confirmando,
              onSelecionar: (id) => setState(() {
                _provedorSelecionado = id;
                _recusa = null;
              }),
              onConfirmar: _confirmar,
            ),
        },
      ),
    );
  }
}

class _Formas extends StatelessWidget {
  final List<ProvedorPagamento> provedores;
  final String? selecionado;
  final TextEditingController credencial;
  final String? recusa;
  final String? erro;
  final bool confirmando;
  final ValueChanged<String> onSelecionar;
  final ValueChanged<ProvedorPagamento> onConfirmar;

  const _Formas({
    required this.provedores,
    required this.selecionado,
    required this.credencial,
    required this.recusa,
    required this.erro,
    required this.confirmando,
    required this.onSelecionar,
    required this.onConfirmar,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final atual = provedores.where((p) => p.id == selecionado).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Com uma única forma disponível, a lista de opções vira ruído — o
        // provedor já vem pré-selecionado e só o campo aparece.
        if (provedores.length > 1)
          for (final p in provedores) ...[
            InkWell(
              onTap: () => onSelecionar(p.id),
              borderRadius: AppRadius.md,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: p.id == selecionado ? colors.accentSoft : colors.card,
                  borderRadius: AppRadius.md,
                  border: Border.all(
                    color: p.id == selecionado ? colors.accent : colors.border,
                    width: p.id == selecionado ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      p.id == selecionado
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color:
                          p.id == selecionado ? colors.accent : colors.fgSubtle,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.rotulo, style: textTheme.titleMedium),
                          if (p.instrucao.isNotEmpty)
                            Text(
                              p.instrucao,
                              style: textTheme.bodySmall
                                  ?.copyWith(color: colors.fgMuted),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        if (atual != null) ...[
          if (provedores.length == 1 && atual.instrucao.isNotEmpty) ...[
            Text(
              atual.instrucao,
              style: textTheme.bodyMedium?.copyWith(color: colors.fgMuted),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (atual.requerCredencial)
            AppTextField(
              label: atual.rotuloCredencial,
              controller: credencial,
              prefixIcon: Icons.confirmation_number_outlined,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => confirmando ? null : onConfirmar(atual),
            ),
          if (recusa case final msg?) ...[
            const SizedBox(height: AppSpacing.sm),
            CadastroErrorBanner(message: msg),
          ],
          if (erro case final msg?) ...[
            const SizedBox(height: AppSpacing.sm),
            CadastroErrorBanner(message: msg),
          ],
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: atual.modo == ModoConfirmacaoPagamento.assincrona
                ? 'Ir para o pagamento'
                : 'Confirmar',
            isLoading: confirmando,
            onPressed: confirmando ? null : () => onConfirmar(atual),
          ),
        ],
      ],
    );
  }
}
