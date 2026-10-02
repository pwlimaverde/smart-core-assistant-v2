import 'dart:developer' as developer;

import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';

/// P13 — a foto do contato, ou as iniciais quando não há foto.
///
/// P6 — a URL é assinada do R2, com validade de 1 h. Quando ela não abre
/// (venceu, o storage falhou), o avatar avisa [aoFalharFoto] **uma vez** por
/// foto — quem recebe pede o contato de novo, sem forçar o provedor — e cai
/// nas iniciais. Se a URL nova do mesmo objeto também falhar, fica nas
/// iniciais sem pedir de novo: nada de laço de recarga nem erro em log. A
/// imagem quebrada nunca vira um ícone de erro no meio do quadro.
class AvatarDoContato extends StatefulWidget {
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
  State<AvatarDoContato> createState() => _AvatarDoContatoState();
}

class _AvatarDoContatoState extends State<AvatarDoContato> {
  /// A URL exata que já falhou: não se tenta baixá-la de novo a cada
  /// redesenho — vai direto às iniciais.
  String? _urlQueFalhou;

  /// Objetos (caminho no storage, sem a assinatura da query string) que já
  /// pediram recarga. Uma URL recém-assinada do mesmo objeto não pede outra;
  /// uma foto nova (outro caminho) pode pedir uma vez.
  final _objetosQuePediram = <String>{};

  void _aoFalhar() {
    final url = widget.fotoUrl;
    if (_urlQueFalhou == url) return;
    _urlQueFalhou = url;
    final callback = widget.aoFalharFoto;
    if (callback == null) return;
    final objeto = Uri.tryParse(url)?.path ?? '';
    if (!_objetosQuePediram.add(objeto)) return;
    // Nunca a URL (é credencial) nem o telefone: só o fato.
    developer.log(
      'foto do contato não abriu; pedindo o contato de novo',
      name: 'operacional_module.contatos',
      level: 500,
    );
    // O `errorBuilder` roda durante o build: quem recebe o aviso pode querer
    // `setState`, então o aviso sai depois do quadro.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) callback();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final raio = widget.raio;
    // O avatar sem foto é o dourado da marca com as iniciais em branco, como
    // em todo o workspace (`ws-card__av`, `ws-chat__av`, `ws-info__av`).
    final semFoto = CircleAvatar(
      radius: raio,
      backgroundColor: colors.accent,
      child: Text(
        AvatarDoContato.iniciais(widget.nome),
        style: TextStyle(
          fontSize: raio * 0.72,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    final url = widget.fotoUrl;
    if (url.isEmpty || url == _urlQueFalhou) return semFoto;
    return ClipOval(
      child: Image.network(
        url,
        width: raio * 2,
        height: raio * 2,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) {
          _aoFalhar();
          return semFoto;
        },
      ),
    );
  }
}
