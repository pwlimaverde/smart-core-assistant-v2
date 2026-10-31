import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/documentos_da_conversa.dart';

void main() {
  group('DocumentosDaConversa', () {
    test('CPF e CNPJ conferem o dígito verificador', () {
      expect(DocumentosDaConversa.cpfValido('52998224725'), isTrue);
      expect(DocumentosDaConversa.cpfValido('52998224726'), isFalse);
      expect(DocumentosDaConversa.cpfValido('11111111111'), isFalse);
      expect(DocumentosDaConversa.cpfValido('529982247'), isFalse);
      expect(DocumentosDaConversa.cnpjValido('11222333000181'), isTrue);
      expect(DocumentosDaConversa.cnpjValido('11222333000182'), isFalse);
      expect(DocumentosDaConversa.cnpjValido('00000000000000'), isFalse);
    });

    test('extrai documento válido com ou sem pontuação, sem repetir', () {
      final achados = DocumentosDaConversa.extrair([
        'meu CPF é 529.982.247-25, obrigado',
        'confirmo: 52998224725',
        'CNPJ 11.222.333/0001-81',
      ]);
      expect(achados, ['52998224725', '11222333000181']);
    });

    test('ignora número com dígito errado e telefone', () {
      final achados = DocumentosDaConversa.extrair([
        'CPF 52998224726',
        'ligue para 11 99999-8888',
        '',
      ]);
      expect(achados, isEmpty);
    });

    test('mesmosDocumentos compara a ordem', () {
      expect(DocumentosDaConversa.mesmosDocumentos(['a'], ['a']), isTrue);
      expect(DocumentosDaConversa.mesmosDocumentos(['a'], ['b']), isFalse);
      expect(DocumentosDaConversa.mesmosDocumentos(const [], const []), isTrue);
    });
  });
}
