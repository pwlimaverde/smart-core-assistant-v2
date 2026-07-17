/// Inicialização do binding FFI (utilitários padrão do flutter_rust_bridge).
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
