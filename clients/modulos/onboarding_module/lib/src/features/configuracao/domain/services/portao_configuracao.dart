import 'package:dependencies_module/dependencies_module.dart';

import '../usecases/configuracao_usecases.dart';

/// Guarda, em memória, se a configuração inicial ainda está pendente.
///
/// Existe porque o guard de rota é **síncrono** e a verdade sobre o progresso
/// mora no servidor. Este objeto consulta uma vez por sessão e notifica; o
/// guard só lê o resultado.
///
/// O estado tem três valores, não dois, e a diferença importa:
///  - `null`  — ainda não sabemos (a consulta está em voo ou nunca rodou);
///  - `true`  — o roteiro não terminou: o app deve voltar para ele;
///  - `false` — terminou (ou o servidor não respondeu): segue para o workspace.
///
/// Falha de consulta resolve para `false` de propósito. Prender alguém no
/// roteiro por causa de uma consulta que falhou seria pior do que deixá-lo
/// entrar no workspace: o roteiro é retomável a qualquer momento, e o
/// workspace não some.
///
/// O mesmo objeto expõe o **estado da conta** ([pagamentoPendente]), que vem na
/// mesma consulta — não há ida extra ao servidor. A regra de falha é idêntica e
/// pela mesma razão: mandar pagar de novo quem já pagou, por causa de uma
/// consulta que falhou, é pior do que deixar entrar. O `data_postgres` continua
/// recusando as escritas de quem está inadimplente, então o pior caso é um
/// aviso que não aparece.
final class PortaoConfiguracao extends ChangeNotifier {
  final ConsultarProgressoUsecase _consultar;

  PortaoConfiguracao({required ConsultarProgressoUsecase consultar})
    // ignore: prefer_initializing_formals
    : _consultar = consultar;

  bool? _pendente;
  int _passo = 5;
  bool _consultando = false;
  bool? _pagamentoPendente;
  String _assinaturaStatus = '';
  String _planoNome = '';

  /// `null` enquanto não se sabe. Ver a nota da classe.
  bool? get pendente => _pendente;

  /// Passo gravado no servidor (5..8). Só faz sentido quando [pendente] é true.
  int get passo => _passo;

  /// `null` enquanto não se sabe; `true` = conta não está em dia.
  bool? get pagamentoPendente => _pagamentoPendente;

  /// `PENDING_PAYMENT`, `ACTIVE`, `SUSPENDED`… Vazio = sem assinatura.
  String get assinaturaStatus => _assinaturaStatus;

  /// Nome do plano, para a tela de pagamento dizer o que está sendo cobrado.
  String get planoNome => _planoNome;

  /// Consulta o servidor, no máximo uma vez por vez.
  ///
  /// Idempotente: chamadas concorrentes (o guard reavalia a cada navegação)
  /// não viram várias consultas.
  Future<void> avaliar() async {
    if (_consultando || _pendente != null) return;
    _consultando = true;

    final res = await _consultar(noParams);
    _consultando = false;

    switch (res) {
      case Success(:final value):
        _pendente = !value.concluido;
        _passo = value.passo;
        _pagamentoPendente = value.pagamentoPendente;
        _assinaturaStatus = value.assinaturaStatus;
        _planoNome = value.planoNome;
      case Failure():
        _pendente = false;
        _pagamentoPendente = false;
    }
    notifyListeners();
  }

  /// Marca a conta como em dia sem ida ao servidor — para a tela de pagamento,
  /// que acabou de quitar e não deve esperar outra consulta para liberar a
  /// navegação. Mesmo padrão de [concluir].
  void quitar() {
    if (_pagamentoPendente == false) return;
    _pagamentoPendente = false;
    _assinaturaStatus = 'ACTIVE';
    notifyListeners();
  }

  /// Marca o roteiro como concluído sem ida ao servidor — para a tela final,
  /// que acabou de gravar a conclusão e não deve esperar outra consulta.
  void concluir() {
    if (_pendente == false) return;
    _pendente = false;
    notifyListeners();
  }

  /// Esquece o que sabia. Chamado no logout: a próxima sessão pode ser de
  /// outro tenant, com outro progresso.
  void limpar() {
    _pendente = null;
    _passo = 5;
    _consultando = false;
    _pagamentoPendente = null;
    _assinaturaStatus = '';
    _planoNome = '';
    notifyListeners();
  }
}
