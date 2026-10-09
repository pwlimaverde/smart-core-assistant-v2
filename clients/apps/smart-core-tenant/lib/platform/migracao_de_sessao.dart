// Seleção por import condicional, como em `auto_update.dart`: `dart:io` não
// existe na Web.
export 'migracao_de_sessao_native.dart'
    if (dart.library.js_interop) 'migracao_de_sessao_web.dart';
