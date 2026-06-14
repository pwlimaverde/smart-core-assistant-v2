import 'package:flutter/foundation.dart';

/// Sinaliza a conclusão do boot em estágios. Usado como refreshListenable do
/// GoRouter: ao completar, o redirect reavalia e libera as rotas.
final class BootState extends ValueNotifier<bool> {
  BootState() : super(false);
  void complete() => value = true;
}
