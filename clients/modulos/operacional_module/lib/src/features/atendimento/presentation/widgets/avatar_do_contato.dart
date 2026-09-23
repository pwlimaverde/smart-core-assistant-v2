import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';

/// P13 — a foto do contato, ou as iniciais quando não há foto.
///
/// A URL vem do CDN do WhatsApp, assinada e com validade: ela quebra sozinha
/// depois de alguns dias. A imagem quebrada vira iniciais — nunca um ícone de
/// erro no meio do quadro — e [aoFalharFoto] avisa quem pode pedir uma nova.
class AvatarDoContato extends StatelessWidget {
  final String nome;
  final String fotoUrl;
  final double raio;
  final VoidCallback? aoFalharFoto;

  const AvatarDoContato({
    super.key,
    required this.nome,
    required this.fotoUrl,
    this.raio = 16,
    this.aoFalharFoto,
  });

  /// Duas iniciais do nome; o primeiro dígito do número quando o "nome" é o
  /// telefone; "?" quando não há nada.
  static String iniciais(String nome) {
    final partes = nome
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first.substring(0, 1).toUpperCase();
    return (partes.first.substring(0, 1) + partes.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final semFoto = CircleAvatar(
      radius: raio,
      backgroundColor: colors.border,
      child: Text(
        iniciais(nome),
        style: TextStyle(
          fontSize: raio * 0.8,
          color: colors.fgStrong,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    if (fotoUrl.isEmpty) return semFoto;
    return ClipOval(
      child: Image.network(
        fotoUrl,
        width: raio * 2,
        height: raio * 2,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) {
          aoFalharFoto?.call();
          return semFoto;
        },
      ),
    );
  }
}
