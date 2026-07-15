import 'package:app_config/app_config.dart';

import 'bootstrap.dart';

void main() => bootstrap(
  const AppConfig(
    flavor: AppFlavor.dev,
    apiEndpoint: String.fromEnvironment(
      'SMARTCORE_API_ENDPOINT',
      defaultValue: 'tcp://localhost:50051',
    ),
    enableLogging: true,
  ),
);
