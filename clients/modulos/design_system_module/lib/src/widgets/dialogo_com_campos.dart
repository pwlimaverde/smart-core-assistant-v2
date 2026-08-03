import 'package:flutter/material.dart';

/// Envelope de diálogo que **possui** os `TextEditingController` do conteúdo e
/// os descarta na hora certa.
///
/// Existe por causa de um erro fácil de cometer e difícil de ver: controllers
/// criados antes do `showDialog` nunca são descartados, e `TextEditingController`
/// é `ChangeNotifier` — os listeners sobrevivem a cada janela aberta.
///
/// A saída óbvia **não funciona**:
///
/// ```dart
/// showDialog(...).whenComplete(() => controller.dispose());  // ERRADO
/// ```
///
/// O `whenComplete` dispara quando a rota é removida, mas a animação de
/// fechamento ainda está correndo e os `TextField` seguem lendo o controller —
/// o resultado é `A TextEditingController was used after being disposed`.
///
/// Quem sabe o momento certo é um widget **dentro** da própria rota do diálogo:
/// o `dispose` dele só roda quando a árvore saiu de vez. É o que esta classe
/// faz.
///
/// ```dart
/// showDialog(
///   context: context,
///   builder: (_) => DialogoComCampos(
///     campos: [nomeController, emailController],
///     builder: (_) => AlertDialog(...),
///   ),
/// );
/// ```
///
/// Os controllers passam a pertencer a este widget: quem os cria não deve
/// descartá-los, e não devem ser reaproveitados depois que a janela fecha.
final class DialogoComCampos extends StatefulWidget {
  /// Controllers a descartar quando o diálogo sair da árvore.
  final List<TextEditingController> campos;

  /// Conteúdo do diálogo — tipicamente um `AlertDialog`, direto ou dentro de
  /// um `StatefulBuilder`.
  final WidgetBuilder builder;

  const DialogoComCampos({
    super.key,
    required this.campos,
    required this.builder,
  });

  @override
  State<DialogoComCampos> createState() => _DialogoComCamposState();
}

class _DialogoComCamposState extends State<DialogoComCampos> {
  @override
  void dispose() {
    for (final campo in widget.campos) {
      campo.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
