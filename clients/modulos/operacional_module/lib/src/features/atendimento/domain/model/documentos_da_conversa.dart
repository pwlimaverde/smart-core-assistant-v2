import 'package:flutter/foundation.dart' show listEquals;

/// V3 (primeira fatia) — CPF e CNPJ que o cliente escreveu na conversa.
///
/// Só entra documento com dígito verificador válido. A sugestão de vínculo
/// exige, além disso, que o documento bata com um cliente já cadastrado, e
/// quem confirma é o atendente. Nenhum documento vai para log.
abstract final class DocumentosDaConversa {
  static bool cpfValido(String cpf) {
    if (cpf.length != 11 || !_somenteDigitos(cpf) || _todosIguais(cpf)) {
      return false;
    }
    final d = _digitos(cpf);
    int dv(int n) {
      var soma = 0;
      for (var i = 0; i < n; i++) {
        soma += d[i] * (n + 1 - i);
      }
      final resto = soma * 10 % 11;
      return resto == 10 ? 0 : resto;
    }

    return dv(9) == d[9] && dv(10) == d[10];
  }

  static bool cnpjValido(String cnpj) {
    if (cnpj.length != 14 || !_somenteDigitos(cnpj) || _todosIguais(cnpj)) {
      return false;
    }
    final d = _digitos(cnpj);
    const pesos1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    const pesos2 = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    int dv(List<int> pesos, int n) {
      var soma = 0;
      for (var i = 0; i < n; i++) {
        soma += pesos[i] * d[i];
      }
      final resto = soma % 11;
      return resto < 2 ? 0 : 11 - resto;
    }

    return dv(pesos1, 12) == d[12] && dv(pesos2, 13) == d[13];
  }

  /// Documentos válidos achados nos textos, sem repetição e na ordem em que
  /// aparecem. Aceita pontuação (`529.982.247-25`) ou só dígitos.
  static List<String> extrair(Iterable<String> textos) {
    final candidato = RegExp(r'\d[\d.\-/]*\d');
    final achados = <String>[];
    for (final texto in textos) {
      for (final m in candidato.allMatches(texto)) {
        final digitos = m.group(0)!.replaceAll(RegExp(r'\D'), '');
        final valido =
            (digitos.length == 11 && cpfValido(digitos)) ||
            (digitos.length == 14 && cnpjValido(digitos));
        if (valido && !achados.contains(digitos)) achados.add(digitos);
      }
    }
    return achados;
  }

  /// Mesma lista de documentos, na mesma ordem. Usado para saber se a
  /// sugestão precisa ser refeita.
  static bool mesmosDocumentos(List<String> a, List<String> b) =>
      listEquals(a, b);

  static bool _somenteDigitos(String s) =>
      s.codeUnits.every((c) => c >= 48 && c <= 57);

  static bool _todosIguais(String s) =>
      s.codeUnits.every((c) => c == s.codeUnits.first);

  static List<int> _digitos(String s) => [for (final c in s.codeUnits) c - 48];
}
