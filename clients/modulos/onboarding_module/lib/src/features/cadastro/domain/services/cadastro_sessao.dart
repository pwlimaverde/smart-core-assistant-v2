import 'package:meta/meta.dart';

/// Estado do cadastro em andamento, compartilhado entre as quatro telas.
///
/// Existe porque o wizard atravessa rotas: cada rota registra o seu controller
/// num escopo que morre ao sair, mas `tenant_id` e `signup_token` precisam
/// sobreviver do passo 1 ao 4. É um singleton global, registrado pelo módulo.
///
/// **Vive só em memória, de propósito.** Nada aqui vai para o armazenamento
/// local: recarregar a página abandona o cadastro, e isso é preferível a deixar
/// um `signup_token` — que autoriza ativar uma conta — persistido no disco de um
/// computador compartilhado. O usuário que fechar o app no meio recomeça; o
/// registro pendente fica no servidor e o superusuário consegue destravá-lo
/// regerando o código de acesso.
final class CadastroSessao {
  String _tenantId = '';
  String _signupToken = '';
  int _planoId = 0;
  String _email = '';
  String _senha = '';

  String get tenantId => _tenantId;
  String get signupToken => _signupToken;
  int get planoId => _planoId;
  String get email => _email;

  /// `true` quando o passo 1 concluiu e os seguintes podem rodar.
  bool get iniciado => _tenantId.isNotEmpty && _signupToken.isNotEmpty;

  /// `true` quando o plano já foi escolhido (pré-requisito do pagamento).
  bool get temPlano => _planoId > 0;

  /// Guarda as credenciais do passo 1 para o login automático do passo 4.
  ///
  /// A senha fica em memória pelo tempo do wizard e é apagada em [encerrar],
  /// chamado assim que a sessão é criada. Sem isto, o usuário teria de digitar
  /// de novo a senha que acabou de definir.
  void registrarCredenciais({required String email, required String senha}) {
    _email = email;
    _senha = senha;
  }

  void registrarInicio({required String tenantId, required String signupToken}) {
    _tenantId = tenantId;
    _signupToken = signupToken;
  }

  void registrarPlano(int planoId) => _planoId = planoId;

  /// A senha, para o login automático. `@internal`: só o controller de conclusão
  /// deve tocar nisto.
  @internal
  String get senha => _senha;

  /// Limpa tudo — inclusive a senha. Chamado ao concluir ou abandonar.
  void encerrar() {
    _tenantId = '';
    _signupToken = '';
    _planoId = 0;
    _email = '';
    _senha = '';
  }
}
