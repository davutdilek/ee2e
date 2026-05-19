import 'package:flutter/material.dart';

import 'ui/connection_screen.dart';

class EE2EApp extends StatelessWidget {
  const EE2EApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EE2E',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F6FEB)),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F6FEB),
          brightness: Brightness.dark,
        ),
      ),
      home: const ConnectionScreen(),
    );
  }
}
