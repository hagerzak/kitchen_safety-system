import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'splash_screen.dart';
import 'app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://recsbpbfmvzqillzqasa.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJlY3NicGJmbXZ6cWlsbHpxYXNhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQ3MjIxODYsImV4cCI6MjA3MDI5ODE4Nn0.DJOEtld0vWqPMbp91OkZqtD2vI3DVmFRV6RGUGLtxI4',
  );
  runApp(const KitchenSafetyApp());
}

class KitchenSafetyApp extends StatelessWidget {
  const KitchenSafetyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kitchen Safety',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme.copyWith(
        textTheme: ThemeData.light().textTheme.apply(fontFamily: 'OpenSans'),
      ),
      darkTheme: AppTheme.creamyTheme.copyWith(
        textTheme: ThemeData.light().textTheme.apply(fontFamily: 'OpenSans'),
      ),
      themeMode: ThemeMode.system,
      home: const SplashScreen(),
    );
  }
}
