// Seleção por import condicional, como em `url_strategy.dart`: o
// `velopack_flutter` é FFI de desktop e não pode entrar no bundle Web
// (`--wasm`). Na Web cai no no-op.
export 'auto_update_native.dart'
    if (dart.library.js_interop) 'auto_update_web.dart';
export 'update_checker.dart';
