// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'controllers/dashboard_controller.dart';
import 'controllers/auth_controller.dart';
import 'screens/login.dart';
import 'theme/app_theme.dart'; // Importação do tema

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthController()),
        ChangeNotifierProxyProvider<AuthController, DashboardController>(
          create: (_) => DashboardController(),
          update: (_, auth, previous) {
            final controller = previous ?? DashboardController();
            if (auth.empresaIdLogada != null &&
                auth.empresaIdLogada!.isNotEmpty) {
              controller.inicializarDados(auth.empresaIdLogada!);
            }
            return controller;
          },
        ),
      ],
      child: const SmartLogApp(),
    ),
  );
}

class SmartLogApp extends StatelessWidget {
  const SmartLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartLog',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme, // Aplicação da paleta unificada
      home: const TelaLogin(),
    );
  }
}
