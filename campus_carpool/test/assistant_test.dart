import 'dart:convert';

import 'package:campus_carpool/models.dart';
import 'package:campus_carpool/screens/help_chat_screen.dart';
import 'package:campus_carpool/screens/post_ride_screen.dart';
import 'package:campus_carpool/services/assistant_service.dart';
import 'package:campus_carpool/services/firestore_service.dart';
import 'package:campus_carpool/services/http_service.dart';
import 'package:campus_carpool/services/offline_guide.dart';
import 'package:campus_carpool/services/voice_input_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_data.dart';
import 'helpers.dart';

/// Assistant scénarisé : renvoie les réponses prévues, dans l'ordre, et garde ce que l'app lui envoie.
class FakeAssistant extends AssistantService {
  FakeAssistant(this.turns);
  final List<AssistantTurn> turns;
  final messages = <String>[];
  final toolResults = <AssistantToolResult>[];

  @override
  Future<AssistantTurn> send({String? message, List<AssistantToolResult> toolResults = const [], required String lang}) async {
    if (message != null) messages.add(message);
    this.toolResults.addAll(toolResults);
    if (turns.isEmpty) throw AssistantUnavailable('serveur arrêté');
    return turns.removeAt(0);
  }
}

/// Dictée simulée : « entend » la phrase donnée dès que l'on touche le micro.
class FakeVoice extends VoiceInputService {
  FakeVoice(this.heard);
  final String? heard; // null = micro indisponible

  @override
  Future<bool> start({
    required String lang,
    required void Function(String words, bool isFinal) onWords,
    required VoidCallback onStop,
    required ValueChanged<VoiceError> onError,
  }) async {
    if (heard == null) return false;
    if (heard!.isEmpty) {
      onError(VoiceError.permission);
      onStop();
      return true;
    }
    onWords(heard!, true);
    onStop();
    return true;
  }

  @override
  Future<void> stop() async {}
}

AssistantTurn tool(String name, Map<String, dynamic> input) =>
    AssistantTurn(toolCalls: [AssistantToolCall(id: 't1', name: name, input: input)]);

void main() {
  setUp(() async {
    await fakeDb();
    FirestoreService.uid = 'demo';
  });

  Future<void> open(WidgetTester tester, FakeAssistant assistant,
      {ValueChanged<int>? onNavigate, ValueChanged<RidePrefill>? onPrefill}) async {
    await tester.pumpWidget(testApp(Scaffold(
      body: HelpChatScreen(onNavigate: onNavigate ?? (_) {}, onPrefill: onPrefill ?? (_) {}, assistant: assistant),
    )));
  }

  Future<void> ask(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();
  }

  group('Assistant IA', () {
    testWidgets('cherche de vrais trajets et les affiche en cartes', (tester) async {
      final assistant = FakeAssistant([
        tool('search_rides', {'from': 'ariana', 'to': 'Esprit'}),
        const AssistantTurn(reply: 'Amira part bientôt et il reste des places.'),
      ]);
      await open(tester, assistant);
      await ask(tester, 'un trajet vers Esprit depuis Ariana');

      expect(assistant.messages, ['un trajet vers Esprit depuis Ariana']);
      expect(find.text('Ariana → Esprit Ghazela'), findsOneWidget);
      expect(find.text('Amira part bientôt et il reste des places.'), findsOneWidget);
      // L'assistant reçoit les trajets réels, pas des trajets inventés
      final result = jsonDecode(assistant.toolResults.single.content) as Map<String, dynamic>;
      expect(result['found'], 1);
      expect(result['rides'][0]['driver'], 'Amira');
      expect(assistant.toolResults.single.isError, isFalse);
    });

    testWidgets('le créneau horaire écarte les trajets trop tôt ou trop tard', (tester) async {
      final assistant = FakeAssistant([
        tool('search_rides', {'to': 'Esprit', 'time_from': '23:58', 'time_to': '23:59'}),
        const AssistantTurn(reply: 'Rien à cette heure.'),
      ]);
      await open(tester, assistant);
      await ask(tester, 'un trajet vers minuit');

      expect(jsonDecode(assistant.toolResults.single.content)['found'], 0);
      expect(find.text('Ariana → Esprit Ghazela'), findsNothing);
    });

    testWidgets("propose une alerte, créée seulement quand l'utilisateur touche le bouton", (tester) async {
      final assistant = FakeAssistant([
        tool('propose_alert', {'from': 'Sousse', 'to': 'Esprit', 'max_price': 6}),
        const AssistantTurn(reply: 'Aucun trajet pour le moment.'),
      ]);
      await open(tester, assistant);
      await ask(tester, 'un trajet depuis Sousse');

      expect(find.text('Sousse → Esprit · Max 6 dt'), findsOneWidget);
      expect((await FirestoreService.alerts.get()).docs, isEmpty);

      await tester.tap(find.text('Créer cette alerte'));
      await tester.pumpAndSettle();
      final alerts = (await FirestoreService.alerts.get()).docs;
      expect(alerts.single.data(), containsPair('from', 'Sousse'));
      expect(alerts.single.data(), containsPair('userId', 'demo'));
      expect(find.text('Créer cette alerte'), findsNothing);
    });

    testWidgets('pré-remplit le formulaire de publication', (tester) async {
      RidePrefill? opened;
      final assistant = FakeAssistant([
        tool('prefill_ride_form', {'from': 'Ariana', 'to': 'Esprit', 'date': day(2), 'time': '7:30', 'seats': 2, 'price': 3.5}),
        const AssistantTurn(reply: 'Vérifiez puis publiez.'),
      ]);
      await open(tester, assistant, onPrefill: (p) => opened = p);
      await ask(tester, 'je propose Ariana Esprit après-demain 7h30');
      await tester.tap(find.text('Ouvrir le formulaire pré-rempli'));

      expect(opened!.route, 'Ariana → Esprit');
      expect((opened!.hour, opened!.minute, opened!.seats, opened!.price), (7, 30, 2, 3.5));

      await tester.pumpWidget(testApp(Scaffold(body: PostRideScreen(prefill: opened))));
      for (final value in ['Ariana', 'Esprit', day(2), '07:30', '2', '3.5']) {
        expect(find.widgetWithText(TextFormField, value), findsOneWidget, reason: value);
      }
    });

    testWidgets("ouvre la section demandée par l'assistant", (tester) async {
      int? section;
      final assistant = FakeAssistant([
        tool('open_section', {'section': 'bookings'}),
        const AssistantTurn(reply: 'Vos réservations sont ici.'),
      ]);
      await open(tester, assistant, onNavigate: (i) => section = i);
      await ask(tester, 'où sont mes réservations ?');
      await tester.tap(find.text('Ouvrir cette section'));
      expect(section, 3);
    });

    testWidgets('un outil mal appelé renvoie une erreur au lieu de planter', (tester) async {
      final assistant = FakeAssistant([
        tool('delete_everything', {}),
        const AssistantTurn(reply: 'Je ne peux pas faire cela.'),
      ]);
      await open(tester, assistant);
      await ask(tester, 'supprime tout');
      expect(assistant.toolResults.single.isError, isTrue);
      expect(find.text('Je ne peux pas faire cela.'), findsOneWidget);
    });

    testWidgets('serveur injoignable : le guide hors ligne répond', (tester) async {
      await open(tester, FakeAssistant([]));
      await ask(tester, 'comment annuler une réservation ?');
      expect(find.textContaining('guide hors ligne'), findsOneWidget);
      expect(find.textContaining('Un passager peut annuler'), findsOneWidget);
    });
  });

  group('Dictée vocale', () {
    tearDown(() => VoiceInputService.instance = VoiceInputService());

    testWidgets("la phrase dictée est envoyée à l'assistant", (tester) async {
      VoiceInputService.instance = FakeVoice('un trajet vers Esprit demain');
      final assistant = FakeAssistant([const AssistantTurn(reply: 'Je cherche.')]);
      await open(tester, assistant);
      await tester.tap(find.byIcon(Icons.mic_none_rounded));
      await tester.pumpAndSettle();
      expect(assistant.messages, ['un trajet vers Esprit demain']);
      expect(find.text('Je cherche.'), findsOneWidget);
    });

    testWidgets("micro refusé : le message explique comment l'autoriser", (tester) async {
      VoiceInputService.instance = FakeVoice('');
      final assistant = FakeAssistant([]);
      await open(tester, assistant);
      await tester.tap(find.byIcon(Icons.mic_none_rounded));
      await tester.pumpAndSettle();
      expect(find.textContaining('Le micro est bloqué'), findsOneWidget);
      expect(assistant.messages, isEmpty);
    });

    test("codes d'erreur du navigateur et du téléphone", () {
      expect(VoiceInputService.errorFor('not-allowed'), VoiceError.permission);
      expect(VoiceInputService.errorFor('error_permission'), VoiceError.permission);
      expect(VoiceInputService.errorFor('no-speech'), VoiceError.noSpeech);
      expect(VoiceInputService.errorFor('audio-capture'), VoiceError.noMicrophone);
      expect(VoiceInputService.errorFor('network'), VoiceError.network);
      expect(VoiceInputService.errorFor('aborted'), isNull);
    });

    testWidgets('micro indisponible : un message le dit', (tester) async {
      VoiceInputService.instance = FakeVoice(null);
      final assistant = FakeAssistant([]);
      await open(tester, assistant);
      await tester.tap(find.byIcon(Icons.mic_none_rounded));
      await tester.pumpAndSettle();
      expect(find.textContaining("La dictée vocale n'est pas disponible"), findsOneWidget);
      expect(assistant.messages, isEmpty);
    });
  });

  group('AssistantService', () {
    tearDown(() => AssistantService.tokenProvider = () async => null);

    test('envoie le jeton, la demande et la date ; lit les outils demandés', () async {
      AssistantService.tokenProvider = () async => 'jeton';
      late http.Request sent;
      HttpService.client = MockClient((req) async {
        sent = req;
        return http.Response(
          jsonEncode({
            'sessionId': 's1',
            'reply': '',
            'toolCalls': [
              {'id': 't1', 'name': 'search_rides', 'input': {'to': 'Esprit'}},
            ],
          }),
          200,
        );
      });
      final turn = await AssistantService().send(message: 'vers Esprit', lang: 'fr');

      expect(sent.headers['Authorization'], 'Bearer jeton');
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['message'], 'vers Esprit');
      expect(body['today'], day(0));
      expect(turn.toolCalls.single.name, 'search_rides');
      expect(turn.toolCalls.single.input, {'to': 'Esprit'});
    });

    test('conversation expirée : la demande repart dans une nouvelle conversation', () async {
      AssistantService.tokenProvider = () async => 'jeton';
      final sessions = <Object?>[];
      HttpService.client = MockClient((req) async {
        sessions.add(jsonDecode(req.body)['sessionId']);
        return switch (sessions.length) {
          1 => http.Response(jsonEncode({'sessionId': 'vieille', 'reply': 'ok'}), 200),
          2 => http.Response(jsonEncode({'error': 'session_expired'}), 410),
          _ => http.Response(jsonEncode({'sessionId': 'neuve', 'reply': 'nouvelle conversation'}), 200),
        };
      });
      final service = AssistantService();
      await service.send(message: 'bonjour', lang: 'fr');
      final turn = await service.send(message: 'encore là ?', lang: 'fr');
      expect(turn.reply, 'nouvelle conversation');
      expect(sessions, [null, 'vieille', null]);
    });

    test('serveur arrêté ou non connecté : AssistantUnavailable', () async {
      AssistantService.tokenProvider = () async => 'jeton';
      HttpService.client = MockClient((_) async => throw http.ClientException('connexion refusée'));
      expect(AssistantService().send(message: 'x', lang: 'fr'), throwsA(isA<AssistantUnavailable>()));
      AssistantService.tokenProvider = () async => null;
      expect(AssistantService().send(message: 'x', lang: 'fr'), throwsA(isA<AssistantUnavailable>()));
    });
  });

  group('Modèles et guide hors ligne', () {
    test("RidePrefill ignore les valeurs mal formées de l'IA", () {
      final p = RidePrefill.fromJson({'from': ' Ariana ', 'to': 'Esprit', 'date': 'demain', 'time': '25:00', 'seats': 12, 'price': '3'});
      expect((p.from, p.to), ('Ariana', 'Esprit'));
      expect([p.date, p.hour, p.minute, p.seats, p.price], everyElement(isNull));
    });

    test('le guide hors ligne choisit la réponse et la section', () {
      expect(OfflineGuide.answerKey('Comment annuler ma réservation ?'), 'chat_a_cancel');
      expect(OfflineGuide.destinationFor('annuler ma reservation'), 3);
      expect(OfflineGuide.answerKey('je veux publier un trajet'), 'chat_a_offer');
      expect(OfflineGuide.answerKey('xyz'), 'chat_a_default');
      expect(OfflineGuide.destinationFor('xyz'), isNull);
    });
  });
}
