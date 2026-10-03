import 'package:flutter/material.dart';
import 'package:velopack_flutter/velopack_flutter.dart';
import 'theme/smart_core_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Velopack (auto-update)
  await VelopackApp.build().run();

  runApp(const SmartCoreApp());
}

class SmartCoreApp extends StatelessWidget {
  const SmartCoreApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Core Tenant',
      theme: SmartCoreTheme.lightTheme(),
      darkTheme: SmartCoreTheme.darkTheme(),
      themeMode: ThemeMode.system,
      home: const SmartCoreHome(),
    );
  }
}

class SmartCoreHome extends StatefulWidget {
  const SmartCoreHome({Key? key}) : super(key: key);

  @override
  State<SmartCoreHome> createState() => _SmartCoreHomeState();
}

class _SmartCoreHomeState extends State<SmartCoreHome> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Core Tenant'),
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo / Branding
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  'ST',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Welcome Text
            Text(
              'Bem-vindo ao',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),

            // App Name
            Text(
              'Smart Core Tenant',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 16),

            // Tagline
            Text(
              'Atendimento Inteligente. Sempre Disponível.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),

            // Primary Button
            ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Botão primário clicado!'),
                    backgroundColor: Color(0xFF27AE60),
                  ),
                );
              },
              child: const Text('Iniciar'),
            ),
            const SizedBox(height: 12),

            // Secondary Button
            OutlinedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Botão secundário clicado!'),
                  ),
                );
              },
              child: const Text('Saiba Mais'),
            ),
            const SizedBox(height: 48),

            // Version Info
            Text(
              'Versão 0.1.0',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Atualizações automáticas ativadas',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Example: Using Custom Colors
class BrandedCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const BrandedCard({
    Key? key,
    required this.title,
    required this.subtitle,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: SCColors.primary.withOpacity(0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: SCColors.primary,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
