import 'package:dependencies_module/dependencies_module.dart';

import '../controllers/initial_loading_controller.dart';

/// Página de splash: dispara o bootstrap e aguarda em silêncio.
///
/// Não exibe nada visível no sucesso — quem navega é o redirect do GoRouter
/// ao detectar BootState.value = true. Em erro, mostra a mensagem do AppError.
class InitialLoadingPage extends ModulePage<InitialLoadingController, void> {
  const InitialLoadingPage({super.key});

  @override
  void onInit(BuildContext context) => controller.bootstrap();

  @override
  Widget onSuccess(BuildContext context, void _) => const SizedBox.shrink();

  @override
  Widget onLoading(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));

  @override
  Widget onError(BuildContext context, AppError error) => Scaffold(
    body: AppErrorView(message: error.message, onRetry: controller.bootstrap),
  );
}
