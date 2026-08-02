/// Predicados e mapeamentos de rota do onboarding, para o guard do app.
///
/// Vivem aqui, e não em constantes dentro do guard, porque quem sabe quais
/// caminhos o roteiro ocupa é o módulo que os registra. Funções puras, sem
/// dependência de UI ou DI — o guard do app é testável na VM.
library;

/// Rotas do wizard de criação de conta (públicas: quem passa por elas ainda não
/// tem sessão).
bool ehRotaDeCadastro(String location) =>
    location == '/cadastro' || location.startsWith('/cadastro/');

/// Rotas da configuração inicial guiada (exigem sessão: acontecem depois de a
/// conta existir).
bool ehRotaDeConfiguracao(String location) =>
    location == '/configuracao' || location.startsWith('/configuracao/');

/// Rota da tela correspondente ao passo gravado no servidor.
///
/// O roteiro vai do passo 5 ao 8. Qualquer valor fora da faixa cai na primeira
/// tela: é o começo do roteiro e repeti-la não perde nada — melhor do que
/// deixar o cliente num limbo por causa de um número inesperado.
String rotaDeConfiguracaoDoPasso(int passo) => switch (passo) {
      6 => '/configuracao/departamento',
      7 => '/configuracao/assistente',
      8 => '/configuracao/pronto',
      _ => '/configuracao/whatsapp',
    };
