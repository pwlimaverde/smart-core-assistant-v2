// P2b — apaga o arquivo temporário do áudio gravado.
//
// Import condicional, como o aviso nativo: no desktop o gravador escreve num
// arquivo de verdade (na pasta temporária, que tem o usuário do Windows no
// caminho); na web ele devolve um blob e não há o que apagar no disco. Sem
// isto, `dart:io` entraria na compilação web do painel.
export 'apagar_arquivo_web.dart' if (dart.library.io) 'apagar_arquivo_io.dart';
