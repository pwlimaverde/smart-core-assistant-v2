import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    // Build web (e qualquer build sem code assets): não há o que compilar. O
    // hook original lia `input.config.code` aqui e derrubava o
    // `flutter build web`.
    if (!input.config.buildCodeAssets) {
      return;
    }

    // O app tenant só é distribuído como desktop no Windows. Linux/macOS (o
    // `flutter test` do CI roda em Linux) pulam a compilação do crate: o código
    // Dart só chama o Velopack com `Platform.isWindows`.
    if (input.config.code.targetOS != OS.windows) {
      return;
    }

    await const RustBuilder(
      assetName: 'src/lib.rs',
      cratePath: 'rust',
    ).run(input: input, output: output);
  });
}
