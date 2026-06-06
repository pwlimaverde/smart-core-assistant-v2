# Document Loaders (pypdf, python-docx, pillow)

- **Versões Recomendadas:** `pypdf` (4.2.0), `python-docx` (1.1.2), `pillow` (10.3.0)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
- **Propósito no Projeto:** Extração e processamento de textos de mídias e documentos enviados por contatos via WhatsApp para ingestão e leitura da Inteligência Artificial.
- **Documentação Oficial:** [pypdf](https://pypi.org/project/pypdf/) | [python-docx](https://python-docx.readthedocs.io/) | [pillow](https://pillow.readthedocs.io/)

---

## 1. Contexto e Uso no Projeto

Quando um cliente envia um documento PDF, Word ou uma foto no WhatsApp, o `worker` Rust faz o download da mídia e envia o buffer para o `ia_engine` (Python) gerar uma descrição e análise.
- **`pypdf`**: Extrai texto puro de arquivos PDF de orçamentos, termos e documentação técnica.
- **`python-docx`**: Extrai texto de arquivos do Word.
- **`pillow`**: Lida com imagens, fazendo redimensionamentos para reduzir custos de token de LLMs de visão e validar integridade.

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Extração de Texto de PDFs (`pypdf`)
Sempre implemente limites de tamanho de leitura de páginas e trate exceções de PDFs protegidos por senha ou corrompidos.

```python
from pypdf import PdfReader
import io

def extract_text_from_pdf(pdf_bytes: bytes, max_pages: int = 20) -> str:
    """Extrai texto de um PDF limitando o processamento para evitar gargalos."""
    try:
        # Abre o PDF na memória usando bytes buffer
        reader = PdfReader(io.BytesIO(pdf_bytes))
        
        # Valida se o PDF está criptografado
        if reader.is_encrypted:
            return "Erro: O arquivo PDF enviado está protegido por senha."
            
        extracted_text = []
        pages_to_read = min(len(reader.pages), max_pages)
        
        for page_num in range(pages_to_read):
            page = reader.pages[page_num]
            text = page.extract_text()
            if text:
                extracted_text.append(text)
                
        return "\n".join(extracted_text)
    except Exception as e:
        return f"Erro ao processar o arquivo PDF: {str(e)}"
```

### 2.2 Extração de Texto de DOCX (`python-docx`)
O parsing de Word deve varrer parágrafos e células de tabelas para capturar todo o contexto relevante do documento.

```python
import docx
import io

def extract_text_from_docx(docx_bytes: bytes) -> str:
    """Extrai texto de arquivos Word DOCX lendo parágrafos e tabelas."""
    try:
        doc = docx.Document(io.BytesIO(docx_bytes))
        extracted_text = []
        
        # 1. Ler parágrafos simples
        for paragraph in doc.paragraphs:
            if paragraph.text.strip():
                extracted_text.append(paragraph.text)
                
        # 2. Ler tabelas internas do Word
        for table in doc.tables:
            for row in table.rows:
                row_text = [cell.text.strip() for cell in row.cells if cell.text.strip()]
                if row_text:
                    extracted_text.append(" | ".join(row_text))
                    
        return "\n".join(extracted_text)
    except Exception as e:
        return f"Erro ao processar o arquivo Word: {str(e)}"
```

### 2.3 Processamento e Redimensionamento de Imagens (`pillow`)
Para reduzir custos de tokens e latência ao enviar fotos para LLMs de Visão (como GPT-4o Vision), redimensione imagens de altíssima resolução antes do envio.

```python
from PIL import Image
import io

def optimize_image_for_llm(image_bytes: bytes, max_size: int = 1024) -> bytes:
    """Redimensiona a imagem proporcionalmente mantendo o limite do maior lado."""
    try:
        img = Image.open(io.BytesIO(image_bytes))
        
        # Mantém proporção baseada no tamanho máximo
        img.thumbnail((max_size, max_size), Image.Resampling.LANCZOS)
        
        # Salva o resultado de volta para bytes em formato JPEG compactado
        output_buffer = io.BytesIO()
        img.convert("RGB").save(output_buffer, format="JPEG", quality=85)
        return output_buffer.getvalue()
        
    except Exception as e:
        # Se falhar no processamento de Pillow, retorna os bytes originais como fallback
        return image_bytes
```
