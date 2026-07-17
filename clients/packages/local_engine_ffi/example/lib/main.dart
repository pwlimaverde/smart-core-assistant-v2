import 'package:flutter/material.dart';
import 'package:local_engine_ffi/local_engine_ffi.dart';

// Exemplo mínimo do plugin: inicializa a lib nativa (flutter_rust_bridge) e
// exibe o status. O uso real do `LocalEngineApi` acontece no app do tenant, via
// `LocalEngineFfiDataSource` no `operacional_module`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('local_engine_ffi: lib nativa inicializada.'),
        ),
      ),
    );
  }
}
