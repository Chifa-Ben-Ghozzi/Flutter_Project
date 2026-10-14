import 'package:flutter/material.dart';
import '../api.dart';
import '../widgets.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController();
  final pwd = TextEditingController();
  final name = TextEditingController();
  bool register = false, busy = false;

  Future<void> submit() async {
    if (email.text.trim().isEmpty || pwd.text.isEmpty || (register && name.text.trim().isEmpty)) {
      toast(context, 'Remplissez tous les champs');
      return;
    }
    setState(() => busy = true);
    await guard(context, () => register
        ? Api.register(email.text.trim(), pwd.text, name.text.trim())
        : Api.login(email.text.trim(), pwd.text));
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(children: [
              const Icon(Icons.directions_car, size: 72, color: Colors.indigo),
              const Text('Campus Carpool', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              if (register) ...[
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom complet', border: OutlineInputBorder())),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email universitaire', hintText: 'prenom.nom@univ-lyon1.fr', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(controller: pwd, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe', border: OutlineInputBorder())),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy ? null : submit,
                  child: busy
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(register ? "S'inscrire" : 'Se connecter'),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => register = !register),
                child: Text(register ? 'Déjà un compte ? Connexion' : 'Pas de compte ? Inscription'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
