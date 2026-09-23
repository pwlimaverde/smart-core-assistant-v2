// P16 — aviso do sistema operacional quando uma conversa é atribuída.
//
// Import condicional, como o gateway: o desktop usa a notificação nativa do
// Windows; a web não tem o que mostrar fora da aba e segue com o SnackBar.
export 'aviso_nativo_web.dart'
    if (dart.library.io) 'aviso_nativo_desktop.dart';
