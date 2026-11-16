import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'http_service.dart';

/// Un outil que l'assistant demande à l'app d'exécuter (chercher des trajets, proposer une alerte…).
class AssistantToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> input;
  const AssistantToolCall({required this.id, required this.name, required this.input});
}

/// Ce que l'app renvoie à l'assistant après avoir exécuté un outil.
class AssistantToolResult {
  final String id;
  final String content;
  final bool isError;
  const AssistantToolResult(this.id, this.content, {this.isError = false});

  Map<String, dynamic> toJson() => {'id': id, 'content': content, 'isError': isError};
}

/// Une réponse de l'assistant : du texte et/ou des outils à exécuter avant de continuer.
class AssistantTurn {
  final String reply;
  final List<AssistantToolCall> toolCalls;
  final bool refused;
  const AssistantTurn({this.reply = '', this.toolCalls = const [], this.refused = false});
}

/// Assistant injoignable (serveur arrêté, pas de réseau, clé absente…) : l'écran passe au guide hors ligne.
class AssistantUnavailable implements Exception {
  final String reason;
  AssistantUnavailable(this.reason);
  @override
  String toString() => 'AssistantUnavailable($reason)';
}

/// Dialogue avec le serveur de l'assistant IA (push-server/assistant.js), qui garde la clé de l'API.
/// Une instance = une conversation.
class AssistantService {
  /// Adresse du serveur : `flutter run --dart-define=ASSISTANT_URL=http://192.168.1.20:8787` sur un vrai téléphone.
  /// Par défaut : le PC de développement (10.0.2.2 depuis l'émulateur Android).
  static const _configured = String.fromEnvironment('ASSISTANT_URL');
  static String get baseUrl => _configured.isNotEmpty
      ? _configured
      : (!kIsWeb && defaultTargetPlatform == TargetPlatform.android ? 'http://10.0.2.2:8787' : 'http://localhost:8787');

  /// Jeton de connexion Firebase, vérifié par le serveur. Remplaçable dans les tests.
  static Future<String?> Function() tokenProvider = () async => FirebaseAuth.instance.currentUser?.getIdToken();

  static const _timeout = Duration(seconds: 60);
  static const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  String? _sessionId;

  /// Envoie la demande de l'utilisateur ([message]) ou les résultats des outils ([toolResults]).
  Future<AssistantTurn> send({String? message, List<AssistantToolResult> toolResults = const [], required String lang}) async {
    final (status, body) = await _post(message, toolResults, lang);
    if (status == 200) return _turn(body);
    if (status == 410) {
      // Conversation expirée côté serveur : on en ouvre une nouvelle avec la même demande
      _sessionId = null;
      if (message != null) {
        final (again, retry) = await _post(message, const [], lang);
        if (again == 200) return _turn(retry);
      }
    }
    throw AssistantUnavailable('${body['error'] ?? status}');
  }

  AssistantTurn _turn(Map<String, dynamic> body) {
    _sessionId = body['sessionId'] as String?;
    final calls = body['toolCalls'];
    return AssistantTurn(
      reply: body['reply'] as String? ?? '',
      refused: body['refused'] == true,
      toolCalls: [
        if (calls is List)
          for (final c in calls)
            if (c is Map && c['id'] is String && c['name'] is String)
              AssistantToolCall(
                id: c['id'],
                name: c['name'],
                input: c['input'] is Map ? Map<String, dynamic>.from(c['input']) : const {},
              ),
      ],
    );
  }

  Future<(int, Map<String, dynamic>)> _post(String? message, List<AssistantToolResult> results, String lang) async {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    try {
      final token = await tokenProvider();
      if (token == null) throw AssistantUnavailable('unauthenticated');
      final res = await HttpService.client
          .post(
            Uri.parse('$baseUrl/assistant'),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
            body: jsonEncode({
              if (_sessionId != null) 'sessionId': _sessionId,
              if (message != null) 'message': message,
              if (results.isNotEmpty) 'toolResults': results,
              'lang': lang,
              // Date et heure locales de l'utilisateur, pour comprendre « demain vers 8h »
              'today': '${now.year}-${two(now.month)}-${two(now.day)}',
              'weekday': _weekdays[now.weekday - 1],
              'time': '${two(now.hour)}:${two(now.minute)}',
            }),
          )
          .timeout(_timeout);
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      return (res.statusCode, decoded is Map<String, dynamic> ? decoded : <String, dynamic>{});
    } on AssistantUnavailable {
      rethrow;
    } catch (e) {
      // Serveur arrêté, délai dépassé, réponse illisible…
      throw AssistantUnavailable('$e');
    }
  }
}
