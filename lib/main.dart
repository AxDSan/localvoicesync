import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:convert';
import 'ui/theme/app_theme.dart';
import 'ui/pages/app_shell.dart';
import 'services/state_manager.dart';
import 'ui/widgets/interim_results_window.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // =========================================================================
  // MULTI-WINDOW OVERLAY PROCESS
  // =========================================================================
  // When launched as a secondary process (overlay window), we skip all 
  // window_manager calls because the plugin isn't registered in this process.
  // The native C++ code (my_application.cc) handles all window configuration
  // including: frameless, transparency, click-through, positioning.
  // =========================================================================
  if (args.firstOrNull == 'multi_window') {
    final windowIdString = args[1];
    final argument = args[2].isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(args[2]) as Map);
    
    // DO NOT use window_manager here - it's not registered in secondary process
    // The native C++ ghost window setup handles all window configuration
    debugPrint('DEBUG: [main] Starting overlay process (window ID: $windowIdString)');

    runApp(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: Colors.transparent,
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppTheme.skyBlue,
              brightness: Brightness.dark,
            ),
          ),
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: InterimOverlayUI(
              windowId: windowIdString,
              args: argument,
            ),
          ),
        ),
      ),
    );
    return;
  }

  // =========================================================================
  // MAIN APPLICATION PROCESS
  // =========================================================================
  await windowManager.ensureInitialized();
  
  final container = ProviderContainer();
  
  // Initialize settings
  final settings = container.read(settingsServiceProvider);
  await settings.initialize();
  
  // Initialize VoiceSyncManager
  print('DEBUG: [main] Starting VoiceSyncManager initialization...');
  final manager = container.read(voiceSyncManagerProvider);
  try {
    await manager.initialize();
    print('DEBUG: [main] VoiceSyncManager initialization completed successfully.');
  } catch (e, stack) {
    print('DEBUG: [main] VoiceSyncManager initialization FAILED: $e');
    print('DEBUG: Stack trace: $stack');
  }

  // Initialize Overlay Controller
  container.read(overlayControllerProvider);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const LocalVoiceSyncApp(),
    ),
  );
}

class LocalVoiceSyncApp extends StatelessWidget {
  const LocalVoiceSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LocalVoiceSync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AppShell(),
    );
  }
}
