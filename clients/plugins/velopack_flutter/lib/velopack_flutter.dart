import 'src/rust/api/velopack.dart' as velopack_api;
import 'src/rust/frb_generated.dart';

export 'src/rust/api/velopack.dart' hide initVelopack;
export 'src/rust/core/dart_types.dart';
export 'src/rust/frb_generated.dart' show VelopackRustLib;

/// Initializes the Velopack bridge and configures the update source.
///
/// [url] is the update server URL.
///
/// [channel] overrides the channel that updates are fetched from. When `null`,
/// the channel the app was installed from is used.
///
/// [allowDowngrade] must be `true` to migrate to a version lower than the
/// current one. This is required when switching to a channel whose latest
/// version is older than the installed version. Switching channels takes effect
/// on the next launch, so persist the desired channel and restart the app.
Future<void> initializeVelopack({
  required String url,
  String? channel,
  bool allowDowngrade = false,
}) async {
  await VelopackRustLib.init();
  await velopack_api.initVelopack(
    url: url,
    channel: channel,
    allowDowngrade: allowDowngrade,
  );
}
