import 'dart:developer' as developer;

/// O que o app sabe pedir ao Velopack. A implementação real
/// (`auto_update_native.dart`) chama o `velopack_flutter`; os testes passam
/// uma falsa — assim a decisão "atualiza ou não" roda em qualquer plataforma,
/// sem FFI.
abstract interface class VelopackGateway {
  /// `true` quando o app roda da instalação do Velopack
  /// (`%LocalAppData%\SmartCoreTenant\current\…`, com o `Update.exe` na pasta
  /// de cima). `flutter run` e o zip do build não têm.
  bool get instalado;

  /// Carrega a biblioteca Rust e configura o feed. Os hooks do Setup
  /// (`--veloapp-install`, `--veloapp-uninstall`…) são tratados aqui dentro:
  /// nesses casos o processo termina antes de retornar.
  Future<void> inicializar(String feedUrl);

  /// Consulta `{feedUrl}/releases.{canal}.json`. O canal vem da instalação
  /// (o `vpk pack --channel` gravou `beta` ou `stable` no app instalado).
  Future<bool> haAtualizacao();

  /// Baixa o pacote, aplica e reinicia o app na versão nova. Se der certo,
  /// o processo atual termina aqui dentro.
  Future<void> atualizarEReiniciar();
}

/// Desfecho de uma checagem — vai para o log e para os testes.
enum ResultadoAtualizacao {
  /// Plataforma sem Velopack (Web) ou feed não configurado.
  ignorado,

  /// O app não foi instalado pelo Setup do Velopack. Não há o que atualizar.
  naoInstalado,

  /// Feed consultado; já está na versão mais nova.
  emDia,

  /// Havia versão nova; download + aplicação disparados.
  atualizando,

  /// Rede, feed inválido, pacote corrompido... O app segue na versão atual.
  falhou,
}

/// Auto-update do app desktop (D6).
///
/// Duas etapas, chamadas pelo `bootstrap`:
///   1. [preparar] ANTES do `runApp`: carrega o Velopack, que precisa ver os
///      hooks do Setup o quanto antes (eles encerram o processo);
///   2. [verificar] DEPOIS do `runApp`, sem `await`: a consulta ao feed não
///      segura a primeira tela.
///
/// Política: sem pergunta ao usuário. Se o feed tem versão nova, baixa,
/// aplica e reinicia. Uma falha nunca derruba o app — só fica no log, e a
/// próxima subida tenta de novo.
class UpdateChecker {
  UpdateChecker({
    required this.gateway,
    required this.feedUrl,
    required this.suportado,
  });

  final VelopackGateway gateway;

  /// Base do feed (`https://releases…/feed/beta`). Vazio desliga a checagem.
  final String feedUrl;

  /// `true` só no desktop Windows.
  final bool suportado;

  ResultadoAtualizacao? _preparo;
  bool _pronto = false;

  /// Inicializa o Velopack. Devolve `null` quando está pronto para checar, ou
  /// o motivo de não checar.
  Future<ResultadoAtualizacao?> preparar() async {
    if (_pronto) return null;
    if (_preparo != null) return _preparo;
    if (!suportado || feedUrl.isEmpty) {
      return _preparo = ResultadoAtualizacao.ignorado;
    }
    if (!gateway.instalado) {
      _log('app fora da instalação do Velopack — sem auto-update');
      return _preparo = ResultadoAtualizacao.naoInstalado;
    }
    try {
      await gateway.inicializar(feedUrl);
      _pronto = true;
      return null;
    } catch (e) {
      _log('Velopack não inicializou: $e');
      return _preparo = ResultadoAtualizacao.falhou;
    }
  }

  /// Consulta o feed e, havendo versão nova, atualiza e reinicia.
  Future<ResultadoAtualizacao> verificar() async {
    final motivo = await preparar();
    if (motivo != null) return motivo;

    try {
      if (!await gateway.haAtualizacao()) {
        _log('feed $feedUrl: app em dia');
        return ResultadoAtualizacao.emDia;
      }
      _log('feed $feedUrl: versão nova — baixando e aplicando');
      await gateway.atualizarEReiniciar();
      return ResultadoAtualizacao.atualizando;
    } catch (e) {
      _log('falha na atualização automática: $e');
      return ResultadoAtualizacao.falhou;
    }
  }

  static void _log(String msg) =>
      developer.log(msg, name: 'smart_core_tenant.update');
}
