import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Pourquoi la dictée a échoué (pour afficher un message utile).
enum VoiceError { permission, noSpeech, noMicrophone, network, unavailable }

/// Dictée vocale : transforme la voix en texte avec la reconnaissance vocale de l'appareil
/// (Android, iOS) ou du navigateur (Chrome, Edge).
///
/// La fin de la phrase est décidée ici, pas par le navigateur : la phrase est terminée après
/// [endOfSpeech] de silence une fois que des mots ont été entendus ; si aucun mot n'arrive
/// pendant [noSpeechTimeout], la dictée s'arrête avec l'erreur « rien entendu ».
class VoiceInputService {
  /// Remplaçable dans les tests.
  static VoiceInputService instance = VoiceInputService();

  static const endOfSpeech = Duration(seconds: 2);
  static const noSpeechTimeout = Duration(seconds: 10);

  final _speech = SpeechToText();
  bool _ready = false;
  bool _active = false; // une dictée est en cours
  String _words = '';
  Timer? _timer;
  void Function(String words, bool isFinal)? _onWords;
  VoidCallback? _onStop;
  ValueChanged<VoiceError>? _onError;

  /// Traduit le code d'erreur du navigateur ("not-allowed", "no-speech"…) ou du téléphone
  /// ("error_permission", "error_no_match"…). Null = rien à signaler (arrêt demandé).
  static VoiceError? errorFor(String code) {
    final c = code.toLowerCase();
    if (c.contains('aborted')) return null;
    if (c.contains('not-allowed') || c.contains('permission')) return VoiceError.permission;
    if (c.contains('no-speech') || c.contains('no_match') || c.contains('speech_timeout')) return VoiceError.noSpeech;
    if (c.contains('audio')) return VoiceError.noMicrophone;
    if (c.contains('network')) return VoiceError.network;
    return VoiceError.unavailable;
  }

  /// Commence à écouter dans la langue de l'app. [onWords] reçoit le texte reconnu au fur et à mesure
  /// (`isFinal` quand la phrase est terminée) ; [onStop] est appelé quand l'écoute s'arrête ;
  /// [onError] quand elle échoue (micro refusé, rien entendu…).
  /// Renvoie false si la reconnaissance vocale n'existe pas sur cet appareil ou ce navigateur.
  Future<bool> start({
    required String lang,
    required void Function(String words, bool isFinal) onWords,
    required VoidCallback onStop,
    required ValueChanged<VoiceError> onError,
  }) async {
    try {
      _onWords = onWords;
      _onStop = onStop;
      _onError = onError;
      // Les écouteurs sont fixés une fois pour toutes par initialize : ils passent par les champs ci-dessus
      _ready = _ready ||
          await _speech.initialize(
            onStatus: (status) {
              debugPrint('Dictée vocale : $status');
              // Le navigateur a arrêté d'écouter : on termine avec ce qui a été entendu,
              // ou on signale qu'il n'a rien entendu (plutôt que de s'arrêter sans rien dire)
              if (status == SpeechToText.doneStatus) _words.isEmpty ? _fail(VoiceError.noSpeech) : _finish();
            },
            onError: (e) {
              debugPrint('Dictée vocale, erreur : ${e.errorMsg}');
              final error = errorFor(e.errorMsg);
              // Une phrase déjà entendue part quand même
              if (error == null || (error == VoiceError.noSpeech && _words.isNotEmpty)) {
                _finish();
              } else {
                _fail(error);
              }
            },
          );
      if (!_ready) return false;
      _active = true;
      _words = '';
      final locale = lang == 'en' ? 'en_US' : 'fr_FR';
      await _speech.listen(
        onResult: (r) => _heard(r.recognizedWords, r.finalResult),
        listenOptions: SpeechListenOptions(
          // Le navigateur attend « fr-FR », les téléphones « fr_FR »
          localeId: kIsWeb ? locale.replaceAll('_', '-') : locale,
          partialResults: true,
          listenFor: const Duration(seconds: 40),
        ),
      );
      _restartTimer(noSpeechTimeout, () {
        debugPrint('Dictée vocale : aucun mot en ${noSpeechTimeout.inSeconds} s');
        _fail(VoiceError.noSpeech);
      });
      return true;
    } catch (e) {
      debugPrint('Dictée vocale, échec : $e');
      _active = false;
      _timer?.cancel();
      return false;
    }
  }

  void _restartTimer(Duration after, VoidCallback then) {
    _timer?.cancel();
    _timer = Timer(after, then);
  }

  void _heard(String words, bool isFinal) {
    if (!_active || words.trim().isEmpty) return;
    debugPrint('Dictée vocale, entendu : $words');
    _words = words;
    if (isFinal) return _finish();
    _onWords?.call(words, false);
    _restartTimer(endOfSpeech, _finish); // silence après des mots = fin de la phrase
  }

  /// Fin normale : la phrase entendue (s'il y en a une) est livrée comme définitive.
  void _finish() {
    if (!_active) return;
    _active = false;
    _timer?.cancel();
    if (_words.trim().isNotEmpty) _onWords?.call(_words, true);
    _onStop?.call();
    _speech.stop().catchError((Object e) => debugPrint('Dictée vocale : $e'));
  }

  void _fail(VoiceError error) {
    if (!_active) return;
    _active = false;
    _timer?.cancel();
    _onError?.call(error);
    _onStop?.call();
    _speech.stop().catchError((Object e) => debugPrint('Dictée vocale : $e'));
  }

  /// Arrêt demandé par l'utilisateur : le texte déjà dicté reste dans le champ, sans envoi automatique.
  Future<void> stop() async {
    _active = false;
    _timer?.cancel();
    try {
      await _speech.stop();
    } catch (e) {
      debugPrint('Dictée vocale : $e');
    }
  }
}
