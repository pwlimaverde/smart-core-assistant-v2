import 'package:dependencies_module/dependencies_module.dart';

/// Tela inicial enquanto a checagem de atualização roda, antes da aplicação.
///
/// Espera [verificacao] e só então monta a aplicação com [depois]. Se houver
/// versão nova, o processo reinicia dentro de [verificacao] e esta tela nunca
/// chega ao fim.
class SplashAtualizacao extends StatefulWidget {
  const SplashAtualizacao({
    super.key,
    required this.verificacao,
    required this.depois,
  });

  final Future<void> Function() verificacao;
  final Future<Widget> Function() depois;

  @override
  State<SplashAtualizacao> createState() => _SplashAtualizacaoState();
}

class _SplashAtualizacaoState extends State<SplashAtualizacao> {
  Widget? _app;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    await widget.verificacao();
    final app = await widget.depois();
    if (mounted) setState(() => _app = app);
  }

  @override
  Widget build(BuildContext context) {
    final app = _app;
    if (app != null) return app;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Builder(
        builder: (context) {
          final colors = context.colors;
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogo(height: 88),
                  const SizedBox(height: AppSpacing.xl),
                  SizedBox(
                    width: 180,
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      color: colors.accent,
                      backgroundColor: colors.border,
                      borderRadius: AppRadius.pill,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Verificando atualizações…',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: colors.fgMuted),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
