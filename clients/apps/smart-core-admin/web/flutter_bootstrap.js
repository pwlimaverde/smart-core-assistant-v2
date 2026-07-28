// Bootstrap customizado do Flutter Web.
//
// Existe por um motivo só: apontar o engine para o bundle LOCAL. Por padrão, o
// loader monta a URL do engine (skwasm/CanvasKit) a partir do CDN do Google —
//
//   https://www.gstatic.com/flutter-canvaskit/<engineRevision>/skwasm.js
//
// — e o CSP da borda (`script-src 'self' ...`, `connect-src 'self' ...`) bloqueia
// o carregamento. O sintoma é uma tela em BRANCO com todos os assets em HTTP 200:
// nada falha do lado do servidor, o navegador é que recusa o script.
//
// O `flutter build web` já copia o engine para `canvaskit/` dentro do bundle
// (skwasm.js, skwasm.wasm, skwasm_st.*, canvaskit.wasm), então basta dizer ao
// loader que use esse caminho. O valor é relativo ao `<base href>` da página —
// em produção, `/v2/admin/canvaskit/`.
//
// Alternativa descartada: liberar `https://www.gstatic.com` no CSP. Traria de
// volta uma dependência de CDN externo (privacidade e disponibilidade) para
// buscar arquivos que já estão no nosso próprio bundle.
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
});
