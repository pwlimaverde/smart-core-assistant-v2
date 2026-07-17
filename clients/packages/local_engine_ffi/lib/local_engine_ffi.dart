/// Binding FFI (flutter_rust_bridge) do motor local Rust (`local_engine`).
///
/// Expõe o handle `LocalEngineApi` e seus modelos-espelho (`*Ffi`) ao Dart, além
/// do `RustLib` para inicialização. Só compila em plataformas nativas (desktop):
/// a lib nativa é construída e linkada via Cargokit (`windows/CMakeLists.txt`).
library;

export 'src/rust/api/atendimento.dart';
export 'src/rust/frb_generated.dart' show RustLib;
