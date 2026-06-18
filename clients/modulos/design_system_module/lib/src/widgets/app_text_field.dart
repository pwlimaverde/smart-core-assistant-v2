import 'package:flutter/material.dart';

/// Campo de texto padronizado do design system.
///
/// A aparência (preenchimento, bordas, focus ring gold) vem do
/// [InputDecorationTheme] do tema. Suporta [obscureText] com toggle de
/// visibilidade quando [obscureToggle] é `true`.
class AppTextField extends StatefulWidget {
  final String label;
  final String? hint;
  final String? errorText;
  final TextEditingController? controller;
  final bool obscureText;
  final bool obscureToggle;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final IconData? prefixIcon;
  final TextInputAction? textInputAction;

  const AppTextField({
    super.key,
    required this.label,
    this.hint,
    this.errorText,
    this.controller,
    this.obscureText = false,
    this.obscureToggle = false,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    this.prefixIcon,
    this.textInputAction,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _obscured = widget.obscureText;

  @override
  Widget build(BuildContext context) {
    final showToggle = widget.obscureText && widget.obscureToggle;

    return TextField(
      controller: widget.controller,
      obscureText: _obscured,
      keyboardType: widget.keyboardType,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      textInputAction: widget.textInputAction,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        errorText: widget.errorText,
        prefixIcon: widget.prefixIcon != null ? Icon(widget.prefixIcon) : null,
        suffixIcon: showToggle
            ? IconButton(
                icon: Icon(
                  _obscured ? Icons.visibility_off : Icons.visibility,
                ),
                tooltip: _obscured ? 'Mostrar senha' : 'Ocultar senha',
                onPressed: () => setState(() => _obscured = !_obscured),
              )
            : null,
      ),
    );
  }
}
