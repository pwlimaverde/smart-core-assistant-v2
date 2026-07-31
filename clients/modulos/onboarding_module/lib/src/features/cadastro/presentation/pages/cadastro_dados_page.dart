import 'dart:async';

import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/model/cadastro_models.dart';
import '../controllers/cadastro_controllers.dart';
import '../widgets/cadastro_shell.dart';

/// Passo 1 — dados da empresa e do responsável.
final class CadastroDadosPage extends StatefulWidget {
  const CadastroDadosPage({super.key});

  @override
  State<CadastroDadosPage> createState() => _CadastroDadosPageState();
}

class _CadastroDadosPageState extends State<CadastroDadosPage> {
  late final DadosController _controller;
  final _nome = TextEditingController();
  final _slug = TextEditingController();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _telefone = TextEditingController();

  /// Resultado da última checagem de endereço; `null` = ainda não checado.
  SlugDisponibilidade? _slugStatus;
  Timer? _debounce;
  bool _slugEditadoManualmente = false;

  @override
  void initState() {
    super.initState();
    _controller = inject<DadosController>();
    // Sugere o endereço a partir do nome enquanto o usuário não o edita à mão.
    _nome.addListener(_sugerirSlug);
    _slug.addListener(_agendarChecagem);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nome.dispose();
    _slug.dispose();
    _email.dispose();
    _senha.dispose();
    _telefone.dispose();
    super.dispose();
  }

  void _sugerirSlug() {
    if (_slugEditadoManualmente) return;
    final sugerido = slugSugerido(_nome.text);
    if (_slug.text != sugerido) {
      // `removeListener` evita que a sugestão conte como edição manual.
      _slug.removeListener(_agendarChecagem);
      _slug.text = sugerido;
      _slug.addListener(_agendarChecagem);
      _agendarChecagem();
    }
  }

  /// Espera o usuário parar de digitar antes de perguntar ao servidor: sem isso,
  /// cada tecla vira uma chamada — e a rota é pública, com rate limit.
  void _agendarChecagem() {
    _debounce?.cancel();
    final slug = _slug.text.trim();
    if (slug.isEmpty) {
      setState(() => _slugStatus = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final res = await _controller.verificarSlug(slug);
      if (!mounted) return;
      setState(() {
        _slugStatus = switch (res) {
          Success(:final value) => value,
          // Falha de rede na checagem não vira erro na tela: é conveniência, e
          // o servidor revalida no envio de qualquer jeito.
          Failure() => null,
        };
      });
    });
  }

  void _submeter() {
    _slugEditadoManualmente = true;
    _controller.iniciar(
      nome: _nome.text.trim(),
      slug: _slug.text.trim(),
      email: _email.text.trim(),
      senha: _senha.text,
      telefone: _telefone.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DadosController, ViewState<CadastroIniciado>>(
      bloc: _controller,
      listenWhen: (_, atual) => atual is SuccessState<CadastroIniciado>,
      listener: (context, state) => context.go('/cadastro/plano'),
      builder: (context, state) {
        final carregando = state is LoadingState<CadastroIniciado>;
        final erro = state is ErrorState<CadastroIniciado>
            ? ErrorMessageMapper.map(state.error)
            : null;

        return CadastroShell(
          passo: 1,
          titulo: 'Criar conta',
          subtitulo: 'Comece pelos dados da sua empresa.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                label: 'Nome da empresa',
                controller: _nome,
                prefixIcon: Icons.business_outlined,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Endereço da conta',
                controller: _slug,
                prefixIcon: Icons.link,
                textInputAction: TextInputAction.next,
                onChanged: (_) => _slugEditadoManualmente = true,
              ),
              if (_slugStatus case final s?) ...[
                const SizedBox(height: AppSpacing.xs),
                _SlugFeedback(status: s),
              ],
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'E-mail do responsável',
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                prefixIcon: Icons.mail_outline,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Telefone (opcional)',
                controller: _telefone,
                keyboardType: TextInputType.phone,
                prefixIcon: Icons.phone_outlined,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Senha (mínimo 8 caracteres)',
                controller: _senha,
                obscureText: true,
                obscureToggle: true,
                prefixIcon: Icons.lock_outline,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => carregando ? null : _submeter(),
              ),
              if (erro != null) ...[
                const SizedBox(height: AppSpacing.md),
                CadastroErrorBanner(message: erro),
              ],
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: 'Continuar',
                isLoading: carregando,
                onPressed: carregando ? null : _submeter,
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                child: TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Já tenho conta'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Converte o nome da empresa num endereço plausível.
///
/// Só uma sugestão: a autoridade sobre o que é um endereço válido é do servidor,
/// que revalida no envio. Acentos viram as letras sem acento (`ç` → `c`), o
/// resto que não é letra/dígito vira hífen, e hífens sobrando são colapsados.
String slugSugerido(String nome) {
  const comAcento = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const semAcento = 'aaaaaeeeeiiiiooooouuuucn';

  final buffer = StringBuffer();
  for (final char in nome.toLowerCase().split('')) {
    final idx = comAcento.indexOf(char);
    final normalizado = idx >= 0 ? semAcento[idx] : char;
    final ehValido = RegExp(r'[a-z0-9]').hasMatch(normalizado);
    buffer.write(ehValido ? normalizado : '-');
  }

  return buffer
      .toString()
      .replaceAll(RegExp('-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

class _SlugFeedback extends StatelessWidget {
  final SlugDisponibilidade status;

  const _SlugFeedback({required this.status});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cor = status.disponivel ? colors.success : colors.danger;
    return Row(
      children: [
        Icon(
          status.disponivel ? Icons.check_circle_outline : Icons.error_outline,
          size: 15,
          color: cor,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            status.disponivel ? 'Endereço disponível.' : status.mensagem,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cor),
          ),
        ),
      ],
    );
  }
}
