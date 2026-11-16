import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n.dart';
import '../models.dart';
import '../repositories/alert_repository.dart';
import '../repositories/ride_repository.dart';
import '../routes.dart';
import '../services/assistant_service.dart';
import '../services/exceptions.dart';
import '../services/offline_guide.dart';
import '../services/voice_input_service.dart';
import '../theme.dart';
import '../widgets.dart';

/// Alerte de trajet proposée par l'assistant ; créée seulement si l'utilisateur touche le bouton.
class _AlertProposal {
  const _AlertProposal(this.from, this.to, this.maxPrice);
  final String from;
  final String to;
  final double? maxPrice;

  String get label => [if (from.isNotEmpty) from, if (to.isNotEmpty) to].join(' → ');
}

/// Un élément de la conversation : une bulle de texte, des cartes de trajets ou un bouton d'action.
class _ChatMessage {
  _ChatMessage({
    this.text = '',
    this.isUser = false,
    this.destination,
    this.rides = const [],
    this.alert,
    this.prefill,
    this.offline = false,
  });

  final String text;
  final bool isUser;
  final int? destination; // onglet à ouvrir
  final List<Ride> rides;
  final _AlertProposal? alert;
  final RidePrefill? prefill;
  final bool offline; // réponse du guide hors ligne
  bool alertCreated = false;
}

/// Assistant IA : l'étudiant écrit ou dicte sa demande (« un trajet vers Esprit demain vers 8h »).
/// L'assistant (Claude, via push-server/assistant.js) choisit les outils ; ils sont exécutés ici,
/// avec les droits de l'utilisateur connecté : recherche de trajets, alerte, formulaire pré-rempli.
/// Si le serveur est injoignable, le guide hors ligne répond à la place.
class HelpChatScreen extends StatefulWidget {
  const HelpChatScreen({super.key, required this.onNavigate, required this.onPrefill, this.assistant});

  final ValueChanged<int> onNavigate;

  /// Ouvre le formulaire « Publier » avec les valeurs proposées par l'assistant.
  final ValueChanged<RidePrefill> onPrefill;

  /// Remplaçable dans les tests.
  final AssistantService? assistant;

  @override
  State<HelpChatScreen> createState() => _HelpChatScreenState();
}

class _HelpChatScreenState extends State<HelpChatScreen> {
  static const _suggestions = ['chat_s_ai_search', 'chat_s_ai_offer', 'chat_s_bookings', 'chat_s_profile'];
  static const _sections = {'search': 0, 'post': 1, 'my_rides': 2, 'bookings': 3, 'profile': 4};

  /// Nombre maximum d'allers-retours d'outils pour une seule demande.
  static const _maxToolRounds = 6;

  late final _assistant = widget.assistant ?? AssistantService();
  final _input = TextEditingController();
  final _scrollController = ScrollController();
  late final _messages = <_ChatMessage>[
    // Créé au premier build : on lit la langue via L10nScope (autorisé pendant un build)
    _ChatMessage(text: context.tr('chat_welcome')),
  ];

  bool _busy = false; // l'assistant réfléchit
  bool _listening = false; // dictée vocale en cours
  bool _sendWhenHeard = false; // envoyer la phrase dictée dès qu'elle est terminée
  int? _sectionToOpen; // onglet demandé par l'outil open_section, attaché à la réponse

  @override
  void dispose() {
    if (_listening) VoiceInputService.instance.stop();
    _input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _add(_ChatMessage message) {
    if (!mounted) return;
    setState(() => _messages.add(message));
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ---------- Conversation ----------

  Future<void> _send([String? suggestion]) async {
    final question = (suggestion ?? _input.text).trim();
    if (question.isEmpty || _busy) return;
    final l10n = context.read<L10n>();
    _sectionToOpen = null;
    setState(() {
      _messages.add(_ChatMessage(text: question, isUser: true));
      _input.clear();
      _busy = true;
    });
    _scrollDown();

    try {
      var turn = await _assistant.send(message: question, lang: l10n.lang);
      // L'assistant demande des outils : on les exécute et on lui renvoie les résultats, jusqu'à sa réponse
      for (var round = 0; turn.toolCalls.isNotEmpty && round < _maxToolRounds; round++) {
        final results = <AssistantToolResult>[];
        for (final call in turn.toolCalls) {
          results.add(await _runTool(call));
        }
        if (!mounted) return;
        turn = await _assistant.send(toolResults: results, lang: l10n.lang);
      }
      final text = turn.refused ? l10n.tr('chat_refused') : turn.reply;
      if (text.isNotEmpty || _sectionToOpen != null) {
        _add(_ChatMessage(text: text, destination: _sectionToOpen));
      }
    } on AssistantUnavailable catch (e) {
      debugPrint('Assistant IA : $e');
      _add(_ChatMessage(
        text: l10n.tr(OfflineGuide.answerKey(question)),
        destination: OfflineGuide.destinationFor(question),
        offline: true,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- Outils de l'assistant ----------

  /// Exécute un outil demandé par l'assistant et renvoie le résultat qu'il lira.
  /// Les arguments viennent d'un modèle d'IA : chacun est vérifié avant usage.
  Future<AssistantToolResult> _runTool(AssistantToolCall call) async {
    final args = call.input;
    try {
      switch (call.name) {
        case 'search_rides':
          return AssistantToolResult(call.id, await _searchRides(args));
        case 'propose_alert':
          final from = _text(args['from']) ?? '', to = _text(args['to']) ?? '';
          if (from.isEmpty && to.isEmpty) {
            return AssistantToolResult(call.id, 'Give at least one of from / to.', isError: true);
          }
          _add(_ChatMessage(alert: _AlertProposal(from, to, _number(args['max_price']))));
          return AssistantToolResult(
              call.id, 'A "create this alert" button is now shown. The alert exists only once the user taps it.');
        case 'prefill_ride_form':
          final prefill = RidePrefill.fromJson(args);
          if (prefill.from.isEmpty || prefill.to.isEmpty) {
            return AssistantToolResult(call.id, 'Both from and to are required.', isError: true);
          }
          _add(_ChatMessage(prefill: prefill));
          return AssistantToolResult(
              call.id, 'A button opening the pre-filled form is now shown. The user reviews it and publishes the ride.');
        case 'open_section':
          final section = _sections[args['section']];
          if (section == null) return AssistantToolResult(call.id, 'Unknown section.', isError: true);
          _sectionToOpen = section;
          return AssistantToolResult(call.id, 'A button opening this section will be shown under your reply.');
        default:
          return AssistantToolResult(call.id, 'Unknown tool.', isError: true);
      }
    } on ApiException catch (e) {
      return AssistantToolResult(call.id, e.message, isError: true);
    } on NetworkException {
      return AssistantToolResult(call.id, 'The app is offline: the rides database is unreachable.', isError: true);
    } catch (e) {
      debugPrint('Outil ${call.name} : $e');
      return AssistantToolResult(call.id, 'The tool failed.', isError: true);
    }
  }

  static String? _text(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
  static double? _number(Object? v) => v is num && v >= 0 ? v.toDouble() : null;

  /// "8:05" ou "08:05" -> "08:05" (comme le champ `time` d'un trajet), sinon null.
  static String? _time(Object? v) {
    final m = v is String ? RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(v.trim()) : null;
    return m == null ? null : '${m[1]!.padLeft(2, '0')}:${m[2]}';
  }

  /// Recherche réelle dans Firestore ; affiche les trajets trouvés et les décrit à l'assistant.
  Future<String> _searchRides(Map<String, dynamic> args) async {
    final date = _text(args['date']);
    final maxPrice = _number(args['max_price']);
    final minSeats = args['min_seats'];
    final rides = await RideRepository.search({
      if (_text(args['from']) != null) 'from': _text(args['from'])!,
      if (_text(args['to']) != null) 'destination': _text(args['to'])!,
      if (date != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) 'date': date,
      if (maxPrice != null) 'maxPrice': '$maxPrice',
      if (minSeats is num && minSeats >= 1) 'minSeats': '${minSeats.toInt()}',
    });
    // Créneau horaire : les heures "HH:MM" se comparent comme du texte
    final earliest = _time(args['time_from']), latest = _time(args['time_to']);
    final found = rides
        .where((r) =>
            (earliest == null || r.time.compareTo(earliest) >= 0) && (latest == null || r.time.compareTo(latest) <= 0))
        .toList();
    final shown = found.take(5).toList();
    if (shown.isNotEmpty) _add(_ChatMessage(rides: shown));
    return jsonEncode({
      'found': found.length,
      'shown_as_cards': shown.length,
      'rides': [
        for (final r in found.take(10))
          {
            'from': r.from,
            'to': r.to,
            'date': r.date,
            'time': r.time,
            'price_dt': r.price,
            'seats_left': r.seatsLeft,
            'driver': r.driver?.name,
            'driver_rating': r.driver?.rating,
            'driver_reviews': r.driver?.ratingCount,
            'recurring': r.isRecurring,
            if (r.myBookingStatus != null) 'my_request': r.myBookingStatus,
          },
      ],
    });
  }

  Future<void> _createAlert(_ChatMessage message) async {
    final l10n = context.read<L10n>();
    final alert = message.alert!;
    try {
      await AlertRepository.add(from: alert.from, to: alert.to, maxPrice: alert.maxPrice);
      if (mounted) setState(() => message.alertCreated = true);
    } on ApiException catch (e) {
      // Affiché dans la conversation : un SnackBar serait caché derrière la fenêtre de l'assistant
      _add(_ChatMessage(text: l10n.trServer(e.message)));
    } on NetworkException {
      _add(_ChatMessage(text: l10n.tr('err_server')));
    }
  }

  // ---------- Dictée vocale ----------

  Future<void> _toggleVoice() async {
    if (_listening) {
      // Arrêt manuel : le texte reste dans le champ pour être corrigé avant l'envoi
      _sendWhenHeard = false;
      setState(() => _listening = false);
      await VoiceInputService.instance.stop();
      return;
    }
    final l10n = context.read<L10n>();
    _sendWhenHeard = true;
    setState(() => _listening = true);
    final started = await VoiceInputService.instance.start(
      lang: l10n.lang,
      onWords: (words, isFinal) {
        if (!mounted) return;
        _input.value = TextEditingValue(text: words, selection: TextSelection.collapsed(offset: words.length));
        if (isFinal && _sendWhenHeard) {
          _sendWhenHeard = false;
          setState(() => _listening = false);
          _send();
        }
      },
      onStop: () {
        if (mounted && _listening) setState(() => _listening = false);
      },
      onError: (error) {
        // Une phrase déjà entendue part quand même : pas de message d'erreur dans ce cas
        if (!mounted || (error == VoiceError.noSpeech && _input.text.trim().isNotEmpty)) return;
        _sendWhenHeard = false;
        _add(_ChatMessage(
          text: l10n.tr(switch (error) {
            VoiceError.permission => 'voice_err_permission',
            VoiceError.noSpeech => 'voice_err_no_speech',
            VoiceError.noMicrophone => 'voice_err_no_mic',
            VoiceError.network => 'voice_err_network',
            VoiceError.unavailable => 'voice_unavailable',
          }),
        ));
      },
    );
    if (!started && mounted) {
      setState(() => _listening = false);
      _add(_ChatMessage(text: l10n.tr('voice_unavailable')));
    }
  }

  // ---------- Interface ----------

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Material(
        color: colors.surface,
        child: Column(
          children: [
            _buildHeader(colors),
            if (_messages.length == 1) _buildSuggestions(colors),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                itemCount: _messages.length + (_busy ? 1 : 0),
                itemBuilder: (context, index) =>
                    index == _messages.length ? _buildThinking(colors) : _buildMessage(_messages[index], colors),
              ),
            ),
            _buildComposer(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.seed, AppTheme.violet],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(46),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('chat_title'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  context.tr('chat_subtitle'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: context.tr('close'),
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions(ColorScheme colors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('chat_quick'),
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestions
                .map(
                  (key) => ActionChip(
                    label: Text(context.tr(key)),
                    onPressed: () => _send(context.tr(key)),
                    side: BorderSide(color: colors.outline.withAlpha(75)),
                    backgroundColor: colors.primary.withAlpha(18),
                    labelStyle: TextStyle(
                      color: colors.onSurface,
                      fontSize: 12,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _assistantAvatar(ColorScheme colors) => CircleAvatar(
        radius: 16,
        backgroundColor: colors.primaryContainer,
        child: Icon(Icons.auto_awesome, size: 17, color: colors.primary),
      );

  Widget _buildMessage(_ChatMessage message, ColorScheme colors) {
    if (message.rides.isNotEmpty) return _buildRides(message.rides, colors);
    if (message.alert != null) return _buildAlert(message, colors);
    if (message.prefill != null) return _buildPrefill(message.prefill!, colors);

    final isUser = message.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[_assistantAvatar(colors), const SizedBox(width: 8)],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: isUser ? colors.primary : colors.primary.withAlpha(18),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 5),
                  bottomRight: Radius.circular(isUser ? 5 : 18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.offline)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.cloud_off, size: 13, color: colors.onSurfaceVariant),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            context.tr('chat_offline_note'),
                            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ]),
                    ),
                  if (message.text.isNotEmpty)
                    Text(
                      message.text,
                      style: TextStyle(
                        color: isUser ? colors.onPrimary : colors.onSurface,
                        height: 1.4,
                        fontSize: 13,
                      ),
                    ),
                  if (message.destination != null) ...[
                    if (message.text.isNotEmpty) const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => widget.onNavigate(message.destination!),
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: Text(context.tr('chat_open_section')),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.primary,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 40),
        ],
      ),
    );
  }

  /// Bulle « l'assistant réfléchit ».
  Widget _buildThinking(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        _assistantAvatar(colors),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: colors.primary.withAlpha(18), borderRadius: BorderRadius.circular(18)),
          child: SizedBox(
            width: 36,
            child: LinearProgressIndicator(minHeight: 4, borderRadius: BorderRadius.circular(4)),
          ),
        ),
      ]),
    );
  }

  /// Trajets trouvés : une carte par trajet ; la toucher ouvre le trajet pour demander une place.
  Widget _buildRides(List<Ride> rides, ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.only(left: 40, bottom: 4),
      child: Column(children: [for (final ride in rides) _buildRide(ride, colors)]),
    );
  }

  Widget _buildRide(Ride ride, ColorScheme colors) {
    final muted = colors.onSurfaceVariant;
    final driver = ride.driver;
    final details = [
      if (driver != null) driver.name,
      if (driver?.rating != null) '★ ${driver!.rating}',
      context.tr('seats_left_of', {'left': ride.seatsLeft, 'total': ride.seats}),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.card(colors),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.pushNamed(context, AppRoutes.rideDetails, arguments: ride.id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ride.time, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                Text(friendlyDate(context, ride.dateTime),
                    style: TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(ride.route,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  const SizedBox(height: 2),
                  Text(details,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 11.5)),
                ]),
              ),
              const SizedBox(width: 8),
              PricePill(ride.price),
              Icon(Icons.chevron_right, color: muted, size: 20),
            ]),
          ),
        ),
      ),
    );
  }

  /// Cadre commun aux propositions de l'assistant (alerte, formulaire pré-rempli).
  Widget _buildProposal(ColorScheme colors, {required IconData icon, required String title, required Widget action}) {
    return Padding(
      padding: const EdgeInsets.only(left: 40, bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppTheme.card(colors),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.primary.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: colors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
          ]),
          const SizedBox(height: 10),
          action,
        ]),
      ),
    );
  }

  Widget _buildAlert(_ChatMessage message, ColorScheme colors) {
    final alert = message.alert!;
    final price = alert.maxPrice == null ? '' : ' · ${context.tr('alert_max_price', {'price': fmtPrice(alert.maxPrice!)})}';
    return _buildProposal(
      colors,
      icon: Icons.notifications_active_outlined,
      title: '${alert.label}$price',
      action: message.alertCreated
          ? Row(children: [
              Icon(Icons.check_circle, size: 18, color: statusColor(context, 'accepted')),
              const SizedBox(width: 6),
              Flexible(child: Text(context.tr('alert_created'), style: const TextStyle(fontSize: 12.5))),
            ])
          : FilledButton.tonalIcon(
              onPressed: () => _createAlert(message),
              icon: const Icon(Icons.add_alert_outlined, size: 18),
              label: Text(context.tr('chat_alert_create')),
            ),
    );
  }

  Widget _buildPrefill(RidePrefill prefill, ColorScheme colors) {
    final when = [
      if (prefill.date != null) friendlyDate(context, prefill.date!),
      if (prefill.hour != null) '${two(prefill.hour!)}:${two(prefill.minute!)}',
    ].join(' ');
    return _buildProposal(
      colors,
      icon: Icons.directions_car_outlined,
      title: when.isEmpty ? prefill.route : '${prefill.route} · $when',
      action: FilledButton.tonalIcon(
        onPressed: () => widget.onPrefill(prefill),
        icon: const Icon(Icons.edit_note, size: 18),
        label: Text(context.tr('chat_prefill_open')),
      ),
    );
  }

  Widget _buildComposer(ColorScheme colors) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.outline.withAlpha(75))),
        ),
        child: Row(
          children: [
            // Micro : dicter la demande ; elle part dès que la phrase est terminée
            IconButton(
              tooltip: context.tr(_listening ? 'voice_stop' : 'voice_start'),
              onPressed: _busy ? null : _toggleVoice,
              style: IconButton.styleFrom(
                backgroundColor: _listening ? colors.error : colors.primary.withAlpha(18),
                foregroundColor: _listening ? colors.onError : colors.primary,
              ),
              icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_none_rounded),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: context.tr(_listening ? 'voice_listening' : 'chat_hint'),
                  filled: true,
                  fillColor: colors.primary.withAlpha(18),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: context.tr('send'),
              onPressed: _busy ? null : _send,
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
