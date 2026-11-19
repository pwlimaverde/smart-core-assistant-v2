import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Executa [acao] segurando uma trava exclusiva compartilhada por **todas as
/// abas** da mesma origem (Web Locks API).
///
/// Por que existe: o refresh token é de uso único e o servidor revoga a família
/// inteira quando um token já rotacionado volta a ser usado. Com duas abas
/// abertas — ou o navegador restaurando várias abas ao reabrir — cada uma lia o
/// mesmo token do `localStorage` e renovava em paralelo: a segunda caía na
/// detecção de reuso, a família era revogada e todas as abas voltavam para o
/// login. Com a trava, as renovações entram em fila e cada uma relê o token que
/// a anterior acabou de gravar.
///
/// Sem `navigator.locks` (contexto inseguro ou navegador antigo) roda sem
/// trava — é o comportamento de antes, nunca pior.
Future<T> comTravaEntreAbas<T>(String nome, Future<T> Function() acao) async {
  final navegador = web.window.navigator;
  if (!navegador.has('locks')) return acao();

  late T resultado;
  Object? erro;
  StackTrace? pilha;

  // O erro é guardado e relançado depois, em vez de rejeitar a Promise: a
  // travessia JS embrulharia a exceção e o chamador perderia o tipo original.
  JSPromise<JSAny?> aoObterTrava(web.Lock? _) => () async {
    try {
      resultado = await acao();
    } catch (e, s) {
      erro = e;
      pilha = s;
    }
  }().toJS;

  await navegador.locks.request(nome, aoObterTrava.toJS).toDart;

  if (erro case final e?) Error.throwWithStackTrace(e, pilha!);
  return resultado;
}
