import 'package:flutter/material.dart';

/// Paleta primitiva do design system — cores cruas, sem significado semântico.
///
/// NÃO consuma estas cores diretamente em telas. Use os tokens semânticos
/// (`AppColors`, via `context.colors`), que escolhem o valor certo conforme
/// o tema claro/escuro. Esta paleta existe apenas como fonte das escalas
/// `stone` (neutros quentes) e `gold` (marca), derivadas do Smart Core.
abstract final class AppPalette {
  // --------------------------------------------------------------------------
  // Escala stone (neutros quentes) — base de fundos, textos e bordas.
  // --------------------------------------------------------------------------
  static const Color stone900 = Color(0xFF1C1917);
  static const Color stone700 = Color(0xFF44403C);
  static const Color stone500 = Color(0xFF78716C);
  static const Color stone400 = Color(0xFFA8A29E);
  static const Color stone300 = Color(0xFFD6D3D1);
  static const Color stone200 = Color(0xFFE7E5E4);
  static const Color stone100 = Color(0xFFF5F5F4);
  static const Color white = Color(0xFFFFFFFF);

  // --------------------------------------------------------------------------
  // Escala gold (marca) — acento, estados ativos, focus rings.
  // --------------------------------------------------------------------------
  static const Color gold600 = Color(0xFF8B7355);
  static const Color gold500 = Color(0xFFA98F71);
  static const Color gold50 = Color(0xFFF5EFE7);

  // --------------------------------------------------------------------------
  // Neutros escuros (tema dark) — fundos e superfícies da variante escura.
  // --------------------------------------------------------------------------
  static const Color dark900 = Color(0xFF14110F); // fundo do board
  static const Color dark800 = Color(0xFF1A1714); // painel
  static const Color dark700 = Color(0xFF1F1B18); // card
  static const Color dark600 = Color(0xFF25201C); // card hover / input
  static const Color dark500 = Color(0xFF2B2622); // chip / border
  static const Color dark400 = Color(0xFF3A342E); // border strong
  static const Color darkTopbar = Color(0xFF0E0C0B);

  static const Color darkFg = Color(0xFFC8C0B7);
  static const Color darkFgStrong = Color(0xFFF5EFE7);
  static const Color darkFgMuted = Color(0xFF8B8175);
  static const Color darkFgSubtle = Color(0xFF6B625A);

  // --------------------------------------------------------------------------
  // Feedback — cores de estado (sucesso, aviso, perigo, informação).
  // --------------------------------------------------------------------------
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFD97706);
  static const Color danger = Color(0xFFDC2626);
  static const Color info = Color(0xFF2563EB);

  static const Color successSoft = Color(0x1A22C55E); // rgba(34,197,94,.10)
  static const Color warningSoft = Color(0x1AF59E0B); // rgba(245,158,11,.10)
  static const Color dangerSoft = Color(0x1AEF4444); // rgba(239,68,68,.10)
  static const Color infoSoft = Color(0x1A3B82F6); // rgba(59,130,246,.10)

  // --------------------------------------------------------------------------
  // Acento gold em transparência — superfícies suaves e focus rings.
  // --------------------------------------------------------------------------
  static const Color accentSoft = Color(0x1AA98F71); // rgba(169,143,113,.10)
  static const Color accentRing = Color(0x33A98F71); // rgba(169,143,113,.20)

  // --------------------------------------------------------------------------
  // Chat (estilo WhatsApp) — primitivas reservadas para as telas de chat.
  // Mantidas aqui até existir um token semântico dedicado.
  // --------------------------------------------------------------------------
  static const Color chatBgLight = Color(0xFFEFEAE2);
  static const Color chatBubInLight = Color(0xFFFFFFFF);
  static const Color chatBubOutLight = Color(0xFFD9FDD3);
  static const Color chatBubOutFgLight = Color(0xFF0B3D20);

  static const Color chatBgDark = Color(0xFF100D0B);
  static const Color chatBubInDark = Color(0xFF1F1B18);
  static const Color chatBubOutDark = Color(0xFF2F4434);
  static const Color chatBubOutFgDark = Color(0xFFD6F0C8);
}
