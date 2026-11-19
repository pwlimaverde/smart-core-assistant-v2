/// No desktop há um processo só: o single-flight do `AuthServiceImpl` já basta.
Future<T> comTravaEntreAbas<T>(String nome, Future<T> Function() acao) =>
    acao();
