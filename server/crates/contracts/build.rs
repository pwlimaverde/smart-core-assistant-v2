// contracts/build.rs  (comentários em pt-br)
use std::path::PathBuf;
use std::process::Command;

fn find_flatc() -> String {
    // 1. Tentar rodar "flatc" direto do PATH
    if Command::new("flatc").arg("--version").status().is_ok() {
        return "flatc".to_string();
    }

    // 2. Se falhar, tentar o caminho relativo no workspace
    let local_paths = [
        "../../bin/flatc.exe",
        "../../bin/flatc",
        "../bin/flatc.exe",
        "../bin/flatc",
    ];
    for path in local_paths {
        if std::path::Path::new(path).exists()
            && Command::new(path).arg("--version").status().is_ok()
        {
            return path.to_string();
        }
    }

    panic!("Compilador flatc nao encontrado no PATH nem em server/bin/");
}

fn find_protoc() -> String {
    // 1. Tentar rodar "protoc" direto do PATH
    if Command::new("protoc").arg("--version").status().is_ok() {
        return "protoc".to_string();
    }

    // 2. Se falhar, tentar o caminho relativo no workspace
    let local_paths = [
        "../../bin/protoc.exe",
        "../../bin/protoc",
        "../bin/protoc.exe",
        "../bin/protoc",
    ];
    for path in local_paths {
        if std::path::Path::new(path).exists() {
            if let Ok(abs_path) = std::fs::canonicalize(path) {
                if Command::new(&abs_path).arg("--version").status().is_ok() {
                    return abs_path.to_string_lossy().into_owned();
                }
            }
        }
    }

    panic!("Compilador protoc nao encontrado no PATH nem em server/bin/");
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let schemas = PathBuf::from("schemas");
    let out_fbs = PathBuf::from("generated/fbs");
    let out_rs = std::env::var("OUT_DIR")?;

    // rebuild quando qualquer schema mudar
    println!("cargo:rerun-if-changed=schemas");

    // Configurar localizacao do protoc
    let protoc_bin = find_protoc();
    std::env::set_var("PROTOC", &protoc_bin);

    // lista dos .proto canônicos autorados
    let protos = [
        "schemas/envelope.proto",
        "schemas/errors.proto",
        "schemas/events/message.proto",
        "schemas/events/persistence.proto",
        "schemas/queries/conversation.proto",
        "schemas/queries/auth.proto",
        "schemas/queries/admin.proto",
        "schemas/ai/ai_engine.proto",
    ];

    // (1) gRPC/Protobuf direto do .proto
    tonic_prost_build::configure()
        .build_server(true)
        .build_client(true)
        .compile_protos(&protos, &[schemas.to_str().unwrap()])?;

    // Obter o executável do flatc
    let flatc_bin = find_flatc();

    // (2) .proto → .fbs (best-effort). --oneof-union mapeia oneof→union.
    std::fs::create_dir_all(&out_fbs)?;
    for proto in protos {
        let status = Command::new(&flatc_bin)
            .args(["--proto", "--oneof-union", "-o"])
            .arg(&out_fbs)
            .arg(proto)
            .status()?;
        assert!(status.success(), "flatc --proto falhou para {proto}");
    }

    // --- CONSOLIDAR TODOS OS SCHEMAS FBS EM UM ÚNICO SCHEMA UNIFICADO ---
    // Isto resolve o bug do flatc de imports circulares e namespaces duplicados no Rust.
    let mut unified_fbs = String::new();
    unified_fbs.push_str("// Auto-generated unified FlatBuffers schema\n\n");
    unified_fbs.push_str("namespace smartcore.contracts;\n\n");

    let fbs_entries = std::fs::read_dir(&out_fbs)?;
    for entry in fbs_entries {
        let entry = entry?;
        let path = entry.path();
        if path.extension().is_some_and(|ext| ext == "fbs")
            && path.file_name().unwrap() != "all_schemas.fbs"
        {
            let content = std::fs::read_to_string(&path)?;
            for line in content.lines() {
                let trimmed = line.trim();
                // Ignorar imports (includes) e definicoes de namespace duplicadas
                if trimmed.starts_with("include ")
                    || trimmed.starts_with("namespace ")
                    || trimmed.starts_with("//")
                {
                    continue;
                }

                // Limpar qualificadores absolutos de namespace dentro do schema unificado
                let mut cleaned_line = line.to_string();
                cleaned_line = cleaned_line.replace("smartcore.contracts.events.", "");
                cleaned_line = cleaned_line.replace("smartcore.contracts.queries.", "");
                cleaned_line = cleaned_line.replace("smartcore.contracts.ai.", "");
                cleaned_line = cleaned_line.replace("smartcore.contracts.", "");

                unified_fbs.push_str(&cleaned_line);
                unified_fbs.push('\n');
            }
            unified_fbs.push('\n');
        }
    }

    let all_schemas_path = out_fbs.join("all_schemas.fbs");
    std::fs::write(&all_schemas_path, unified_fbs)?;

    // (3) Compilar apenas o schema unificado em Rust
    let status = Command::new(&flatc_bin)
        .arg("--rust")
        .arg("-o")
        .arg(&out_rs)
        .arg(&all_schemas_path)
        .status()?;
    assert!(
        status.success(),
        "flatc --rust falhou para o all_schemas.fbs"
    );

    Ok(())
}
