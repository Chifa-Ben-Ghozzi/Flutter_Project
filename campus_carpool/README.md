# Campus Carpool (Flutter + Node.js)

## 1. Backend (terminal 1)
    cd backend
    npm install
    npm start          # http://localhost:3000  (données dans backend/db.json)

## 2. App Flutter (terminal 2, à la racine du projet)
    flutter create .   # génère android/ios/web (une seule fois, ne touche pas à lib/)
    flutter pub get
    flutter run        # ou: flutter run -d chrome

### Android uniquement
Dans android/app/src/main/AndroidManifest.xml, ajoutez dans la balise <application ...> :
    android:usesCleartextTraffic="true"
(et <uses-permission android:name="android.permission.INTERNET"/> avant <application>)

### Téléphone réel
Dans lib/api.dart, remplacez l'URL par l'IP de votre PC (ex: http://192.168.1.20:3000).

### iOS
Ajoutez NSPhotoLibraryUsageDescription dans ios/Runner/Info.plist (image_picker).

Emails acceptés : domaine contenant "univ", ".edu" ou ".ac." (ex: prenom@univ-lyon1.fr).
