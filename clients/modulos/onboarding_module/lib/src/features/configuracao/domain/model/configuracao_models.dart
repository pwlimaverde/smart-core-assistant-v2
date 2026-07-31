import 'package:meta/meta.dart';

/// Modelos da configuração inicial guiada (passos 5 a 8).
///
/// O cadastro cria a conta; este roteiro é o que coloca o sistema para operar.

/// Conexão de WhatsApp recém-criada.
@immutable
final class ConexaoWhatsapp {
  final int id;
  final String nome;
  final String provedor;

  const ConexaoWhatsapp({
    required this.id,
    required this.nome,
    required this.provedor,
  });
}

/// Situação do pareamento, consultada em intervalos enquanto o QR está na tela.
@immutable
final class EstadoConexao {
  /// `connected`, `disconnected`, `connecting` ou `unknown`.
  final String estado;

  /// QR em base64. Vazio quando já conectou — ou quando o provedor ainda não o
  /// gerou, que nos primeiros segundos é o normal.
  final String qrCode;

  const EstadoConexao({required this.estado, required this.qrCode});

  bool get conectado => estado == 'connected';

  bool get temQr => qrCode.isNotEmpty;
}

/// Departamento criado no roteiro.
@immutable
final class Departamento {
  final int id;
  final String nome;

  const Departamento({required this.id, required this.nome});
}

/// Progresso registrado no servidor.
@immutable
final class ProgressoOnboarding {
  final int passo;
  final bool concluido;

  const ProgressoOnboarding({required this.passo, required this.concluido});
}
