// Entrypoint padrão — delega para o flavor de desenvolvimento.
// Para produção: flutter run -t lib/main_prod.dart
import 'main_dev.dart' as dev;

void main() => dev.main();
