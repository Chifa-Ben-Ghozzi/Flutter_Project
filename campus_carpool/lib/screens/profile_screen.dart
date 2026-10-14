import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../api.dart';
import '../widgets.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final name = TextEditingController(text: Api.user?['name'] ?? '');
  late final phone = TextEditingController(text: Api.user?['phone'] ?? '');
  late final model = TextEditingController(text: Api.user?['car']?['model'] ?? '');
  late final plate = TextEditingController(text: Api.user?['car']?['plate'] ?? '');

  Future<void> pickPhoto() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 300, imageQuality: 60);
    if (x == null) return;
    final b64 = base64Encode(await x.readAsBytes());
    if (await guard(context, () => Api.updateProfile({'photo': b64}))) setState(() {});
  }

  Future<void> save() async {
    final ok = await guard(context, () => Api.updateProfile({
          'name': name.text.trim(),
          'phone': phone.text.trim(),
          'car': {'model': model.text.trim(), 'plate': plate.text.trim()},
        }));
    if (ok && mounted) toast(context, 'Profil enregistré ✅');
  }

  @override
  Widget build(BuildContext context) {
    final photo = Api.user?['photo'];
    return ListView(padding: const EdgeInsets.all(16), children: [
      Center(
        child: GestureDetector(
          onTap: pickPhoto,
          child: CircleAvatar(
            radius: 50,
            backgroundImage: photo != null ? MemoryImage(base64Decode(photo)) : null,
            child: photo == null ? const Icon(Icons.add_a_photo, size: 36) : null,
          ),
        ),
      ),
      const SizedBox(height: 8),
      Center(child: Text(Api.user?['email'] ?? '', style: const TextStyle(color: Colors.grey))),
      const SizedBox(height: 16),
      TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Téléphone', prefixIcon: Icon(Icons.phone), border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: model, decoration: const InputDecoration(labelText: 'Voiture (modèle, couleur)', prefixIcon: Icon(Icons.directions_car), border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: plate, decoration: const InputDecoration(labelText: 'Plaque', border: OutlineInputBorder())),
      const SizedBox(height: 20),
      FilledButton(onPressed: save, child: const Text('Enregistrer')),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: Api.logout, icon: const Icon(Icons.logout), label: const Text('Se déconnecter')),
    ]);
  }
}
