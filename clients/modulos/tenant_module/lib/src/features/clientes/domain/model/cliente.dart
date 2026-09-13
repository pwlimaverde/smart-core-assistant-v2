import 'package:meta/meta.dart';

/// B10 (N11 E5) — os campos de um cliente, do jeito que a tela os edita.
///
/// CNPJ, CPF e endereço são dado protegido: esta classe nunca vai para log.
@immutable
class DadosCliente {
  final String nomeFantasia;
  final String razaoSocial;
  final String tipo;
  final String cnpj;
  final String cpf;
  final String telefone;
  final String site;
  final String ramoAtividade;
  final String observacoes;
  final String cep;
  final String logradouro;
  final String numero;
  final String complemento;
  final String bairro;
  final String cidade;
  final String uf;

  const DadosCliente({
    required this.nomeFantasia,
    this.razaoSocial = '',
    this.tipo = '',
    this.cnpj = '',
    this.cpf = '',
    this.telefone = '',
    this.site = '',
    this.ramoAtividade = '',
    this.observacoes = '',
    this.cep = '',
    this.logradouro = '',
    this.numero = '',
    this.complemento = '',
    this.bairro = '',
    this.cidade = '',
    this.uf = '',
  });

  bool get pessoaFisica => tipo == 'pf';

  /// O documento que interessa ao tipo, formatado para leitura.
  String get documentoFormatado {
    if (pessoaFisica || (cnpj.isEmpty && cpf.isNotEmpty)) {
      return formatarCpf(cpf);
    }
    return formatarCnpj(cnpj);
  }

  /// "Cidade/UF", ou só o que houver.
  String get localidade =>
      [cidade, uf].where((p) => p.trim().isNotEmpty).join('/');
}

/// Um cliente cadastrado.
@immutable
class Cliente {
  final int id;
  final DadosCliente dados;
  final bool ativo;

  /// Quantos contatos (quem fala pelo WhatsApp) estão ligados a ele.
  final int contatos;

  const Cliente({
    required this.id,
    required this.dados,
    required this.ativo,
    required this.contatos,
  });
}

/// Um contato ligado a um cliente.
@immutable
class ContatoDoCliente {
  final int id;
  final String nome;
  final String telefone;

  const ContatoDoCliente({
    required this.id,
    required this.nome,
    required this.telefone,
  });

  String get exibicao => nome.trim().isNotEmpty ? nome : telefone;
}

String _digitos(String valor) => valor.replaceAll(RegExp(r'\D'), '');

/// `12345678000190` → `12.345.678/0001-90`. Fora do tamanho, devolve o que veio.
String formatarCnpj(String valor) {
  final d = _digitos(valor);
  if (d.length != 14) return valor;
  return '${d.substring(0, 2)}.${d.substring(2, 5)}.${d.substring(5, 8)}/'
      '${d.substring(8, 12)}-${d.substring(12)}';
}

/// `12345678901` → `123.456.789-01`. Fora do tamanho, devolve o que veio.
String formatarCpf(String valor) {
  final d = _digitos(valor);
  if (d.length != 11) return valor;
  return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-'
      '${d.substring(9)}';
}
