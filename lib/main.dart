import 'package:flutter/material.dart';
import 'core/app_theme.dart';
import 'features/camera/presentation/camera_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StreamingApp());
}

class StreamingApp extends StatelessWidget {
  const StreamingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PhoneCam Stream',
      debugShowCheckedModeBanner: false,
      
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      
      home: const CameraScreen(),
    );
  }
}