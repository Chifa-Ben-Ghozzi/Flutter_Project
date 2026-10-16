
import 'package:flutter/material.dart';
import 'api.dart';
import 'l10n.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';

final L10n l10n = L10n();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await l10n.load();
  runApp(const CarpoolApp());
}

class CarpoolApp extends StatelessWidget {
  const CarpoolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: l10n,
      builder: (_, __) => MaterialApp(
        title: 'Campus Carpool',
        debugShowCheckedModeBanner: false,
        locale: Locale(l10n.lang),
        theme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          useMaterial3: true,
        ),
        home: L10nScope(
          l10n: l10n,
          child: SplashScreen(
            init: Api.init,
            next: ValueListenableBuilder<bool>(
              valueListenable: Api.loggedIn,
              builder: (_, logged, __) =>
                  logged ? const HomeScreen() : const AuthScreen(),
            ),
          ),
        ),
      ),
    );
  }
}