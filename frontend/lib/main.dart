import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/api_client.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Discover & cache the backend IP before the UI renders.
  // On physical devices this probes the local network automatically.
  await ApiClient.initBaseUrl();
  runApp(
    const ProviderScope(
      child: StudyIntelliApp(),
    ),
  );
}

class StudyIntelliApp extends ConsumerWidget {
  const StudyIntelliApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    return MaterialApp(
      title: 'StudyIntelli',
      debugShowCheckedModeBanner: false,
      theme: _buildDarkTheme(),
      home: authState.isAuthenticated ? const HomeScreen() : const AuthScreen(),
    );
  }

  ThemeData _buildDarkTheme() {
    const Color primary = Color(0xFF7C5CBF);       // Deep violet
    const Color primaryLight = Color(0xFF9D7FD4);  // Lighter violet
    const Color accent = Color(0xFF58C4DC);        // Cyan accent
    const Color surface = Color(0xFF1E1B2E);       // Dark purple-navy
    const Color surfaceVariant = Color(0xFF2A2641); // Card surface
    const Color background = Color(0xFF13111F);    // Deep background
    const Color onPrimary = Colors.white;
    const Color onSurface = Color(0xFFE8E0FF);
    const Color onSurfaceMuted = Color(0xFF9E99B8);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        onPrimary: onPrimary,
        secondary: accent,
        onSecondary: Colors.black,
        surface: surface,
        onSurface: onSurface,
        surfaceContainerHighest: surfaceVariant,
        background: background,
        onBackground: onSurface,
      ),
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
        iconTheme: IconThemeData(color: onSurfaceMuted),
      ),
      cardTheme: CardThemeData(
        color: surfaceVariant,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF3A3555), width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF3A3555)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF3A3555)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primaryLight, width: 2),
        ),
        labelStyle: const TextStyle(color: onSurfaceMuted),
        hintStyle: const TextStyle(color: onSurfaceMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 4,
        shape: StadiumBorder(),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primaryLight,
        unselectedLabelColor: onSurfaceMuted,
        indicatorColor: primaryLight,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
        dividerColor: Colors.transparent,
        tabAlignment: TabAlignment.start,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: onSurface, fontWeight: FontWeight.w800),
        headlineMedium: TextStyle(color: onSurface, fontWeight: FontWeight.w700),
        titleLarge: TextStyle(color: onSurface, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(color: onSurface, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(color: onSurface),
        bodyMedium: TextStyle(color: onSurfaceMuted),
        labelLarge: TextStyle(color: onSurface, fontWeight: FontWeight.w600),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceVariant,
        contentTextStyle: const TextStyle(color: onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFF2E2A45), thickness: 1),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceVariant,
        labelStyle: const TextStyle(color: onSurface, fontSize: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: const BorderSide(color: Color(0xFF3A3555)),
      ),
    );
  }
}
