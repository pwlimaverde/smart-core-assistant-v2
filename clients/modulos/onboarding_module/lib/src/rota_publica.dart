/// Predicado das rotas públicas do wizard, para o guard do app.
///
/// Vive aqui, e não numa constante dentro do guard, porque quem sabe quais
/// caminhos o wizard ocupa é o módulo que os registra. Função pura, sem
/// dependência de UI ou DI — o guard do app é testável na VM.
bool ehRotaDeCadastro(String location) =>
    location == '/cadastro' || location.startsWith('/cadastro/');
