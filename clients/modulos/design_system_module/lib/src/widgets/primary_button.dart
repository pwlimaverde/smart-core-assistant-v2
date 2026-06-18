import 'package:flutter/material.dart';

/// Botão primário do design system.
///
/// Estilo (cor de acento, altura, raio) vem do [FilledButtonThemeData] do tema,
/// então o botão fica consistente em qualquer tela. Ocupa a largura do pai por
/// padrão; passe [expand] = false para dimensionar pelo conteúdo.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool expand;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.expand = true,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final fg = Theme.of(context).colorScheme.onPrimary;

    final child = isLoading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        : Text(label);

    final button = icon != null && !isLoading
        ? FilledButton.icon(
            onPressed: isLoading ? null : onPressed,
            icon: Icon(icon, size: 18),
            label: child,
          )
        : FilledButton(
            onPressed: isLoading ? null : onPressed,
            child: child,
          );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
