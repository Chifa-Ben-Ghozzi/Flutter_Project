import 'package:flutter/material.dart';
import 'api.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.init();
  runApp(const CarpoolApp());
}

class CarpoolApp extends StatelessWidget {
  const CarpoolApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Campus Carpool',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: ValueListenableBuilder<bool>(
        valueListenable: Api.loggedIn,
        builder: (_, logged, __) => logged ? const HomeScreen() : const AuthScreen(),
      ),
    );
  }
}
