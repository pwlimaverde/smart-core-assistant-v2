import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/model/cadastro_models.dart';
import '../../domain/services/cadastro_sessao.dart';
import '../controllers/cadastro_controllers.dart';
import '../widgets/cadastro_shell.dart';

/// Passo 2 — escolha do plano.
final class CadastroPlanoPage extends StatefulWidget {
  const CadastroPlanoPage({super.key});

  @override
  State<CadastroPlanoPage> createState() => _CadastroPlanoPageState();
}

class _CadastroPlanoPageState extends State<CadastroPlanoPage> {
  late final PlanoController _controller;
  int? _selecionado;
  bool _avancando = false;
  String? _erroAvanco;

  @override
  void initState() {
    super.initState();
    _controller = inject<PlanoController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Chegar aqui sem ter passado pelo passo 1 (link direto, recarga da
      // página) não tem como funcionar: o `signup_token` vive só em memória.
      if (!inject<CadastroSessao>().iniciado) {
        if (mounted) context.go('/cadastro');
        return;
      }
      _controller.carregar();
    });
  }

  Future<void> _avancar() async {
    final plano = _selecionado;
    if (plano == null) return;

    setState(() {
      _avancando = true;
      _erroAvanco = null;
    });
    final res = await _controller.selecionar(plano);
    if (!mounted) return;

    switch (res) {
      case Success():
        context.go('/cadastro/pagamento');
      case Failure(:final error):
        setState(() {
          _avancando = false;
          _erroAvanco = ErrorMessageMapper.map(error);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CadastroShell(
      passo: 2,
      titulo: 'Escolha o plano',
      subtitulo: 'Você pode mudar depois, pelo painel.',
      aoVoltar: () => context.go('/cadastro'),
      child: BlocBuilder<PlanoController, ViewState<List<PlanoPublico>>>(
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
          SuccessState(:final data) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final plano in data) ...[
                  _CartaoPlano(
                    plano: plano,
                    selecionado: _selecionado == plano.id,
                    onTap: () => setState(() => _selecionado = plano.id),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (_erroAvanco case final msg?) ...[
                  const SizedBox(height: AppSpacing.sm),
                  CadastroErrorBanner(message: msg),
                ],
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  label: 'Continuar',
                  isLoading: _avancando,
                  onPressed: _selecionado == null || _avancando ? null : _avancar,
                ),
              ],
            ),
        },
      ),
    );
  }
}

class _CartaoPlano extends StatelessWidget {
  final PlanoPublico plano;
  final bool selecionado;
  final VoidCallback onTap;

  const _CartaoPlano({
    required this.plano,
    required this.selecionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.md,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selecionado ? colors.accentSoft : colors.card,
          borderRadius: AppRadius.md,
          border: Border.all(
            color: selecionado ? colors.accent : colors.border,
            width: selecionado ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selecionado
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selecionado ? colors.accent : colors.fgSubtle,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(plano.nome, style: textTheme.titleMedium),
                      ),
                      // Preço vazio = ainda não definido. Dizer "a combinar" é
                      // mais honesto do que exibir "R$ 0,00".
                      Text(
                        plano.preco.isEmpty
                            ? 'a combinar'
                            : 'R\$ ${plano.preco}',
                        style: textTheme.titleMedium?.copyWith(
                          color: colors.accent,
                        ),
                      ),
                    ],
                  ),
                  if (plano.descricao.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      plano.descricao,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.fgMuted,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.xs,
                    children: [
                      _Limite(
                        icone: Icons.smartphone,
                        texto: '${plano.maxInstancias} WhatsApp',
                      ),
                      _Limite(
                        icone: Icons.view_kanban_outlined,
                        texto: '${plano.maxFluxos} fluxos',
                      ),
                      _Limite(
                        icone: Icons.groups_outlined,
                        texto: '${plano.maxDepartamentos} departamentos',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Limite extends StatelessWidget {
  final IconData icone;
  final String texto;

  const _Limite({required this.icone, required this.texto});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icone, size: 14, color: colors.fgSubtle),
        const SizedBox(width: 4),
        Text(
          texto,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: colors.fgMuted),
        ),
      ],
    );
  }
}
