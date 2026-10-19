import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n.dart';

class _ChatMessage {
  const _ChatMessage({
    required this.text,
    required this.isUser,
    this.destination,
  });

  final String text;
  final bool isUser;
  final int? destination;
}

class HelpChatScreen extends StatefulWidget {
  const HelpChatScreen({super.key, required this.onNavigate});

  final ValueChanged<int> onNavigate;

  @override
  State<HelpChatScreen> createState() => _HelpChatScreenState();
}

class _HelpChatScreenState extends State<HelpChatScreen> {
  static const _suggestions = ['chat_s_find', 'chat_s_bookings', 'chat_s_offer', 'chat_s_profile'];

  final _input = TextEditingController();
  final _scrollController = ScrollController();
  late final _messages = <_ChatMessage>[
    // Créé au premier build : on lit la langue via L10nScope (autorisé pendant un build)
    _ChatMessage(text: context.tr('chat_welcome'), isUser: false),
  ];

  @override
  void dispose() {
    _input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send([String? suggestion]) {
    final question = (suggestion ?? _input.text).trim();
    if (question.isEmpty) return;

    final destination = _destinationFor(question);
    setState(() {
      _messages
        ..add(_ChatMessage(text: question, isUser: true))
        ..add(
          _ChatMessage(
            text: _answer(question),
            isUser: false,
            destination: destination,
          ),
        );
      _input.clear();
    });
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

  String _answer(String question) {
    final tr = context.read<L10n>().tr;
    final text = question.toLowerCase();

    if (_hasAny(text, ['cancel', 'delete', 'annul', 'supprim'])) {
      return tr('chat_a_cancel');
    }
    if (_hasAny(text, ['no rides', 'nothing', 'empty', 'no results', 'not found', 'aucun', 'rien', 'vide'])) {
      return tr('chat_a_empty');
    }
    if (_hasAny(text, ['offer', 'post', 'publish', 'create a ride', 'driver', 'publier', 'proposer', 'conducteur'])) {
      return tr('chat_a_offer');
    }
    if (_hasAny(text, ['accept', 'decline', 'approve', 'passenger', 'request status', 'accepter', 'refuser', 'passager'])) {
      return tr('chat_a_accept');
    }
    if (_hasAny(text, ['book', 'booking', 'reserve', 'reservation', 'request', 'seat', 'place', 'réserv', 'demande'])) {
      return tr('chat_a_booking');
    }
    if (_hasAny(text, [
      'login',
      'log in',
      'sign in',
      'register',
      'account',
      'email',
      'password',
      'inscri',
      'connect',
      'compte',
      'mot de passe'
    ])) {
      return tr('chat_a_account');
    }
    if (_hasAny(text, [
      'profile',
      'photo',
      'phone',
      'car',
      'vehicle',
      'profil',
      'picture',
      'log out',
      'logout',
      'sign out',
      'voiture',
      'téléphone',
      'déconnex'
    ])) {
      return tr('chat_a_profile');
    }
    if (_hasAny(text, [
      'find',
      'search',
      'look for',
      'destination',
      'filter',
      'ride',
      'trajet',
      'chercher',
      'trouver',
      'recherche'
    ])) {
      return tr('chat_a_search');
    }
    if (_hasAny(text, ['hello', 'hi', 'hey', 'help', 'what can you do', 'bonjour', 'salut', 'aide'])) {
      return tr('chat_a_hello');
    }

    return tr('chat_a_default');
  }

  bool _hasAny(String text, List<String> terms) =>
      terms.any((term) => text.contains(term));

  int? _destinationFor(String question) {
    final text = question.toLowerCase();
    if (_hasAny(text, ['cancel', 'delete', 'annul'])) {
      return _hasAny(text, ['booking', 'reservation', 'seat', 'place']) ? 3 : 2;
    }
    if (_hasAny(text, ['offer', 'post', 'publish', 'create a ride', 'publier', 'proposer'])) {
      return 1;
    }
    if (_hasAny(text, ['accept', 'decline', 'approve', 'passenger', 'refuser', 'passager'])) {
      return 2;
    }
    if (_hasAny(text, ['book', 'booking', 'reserve', 'reservation', 'seat', 'place', 'réserv'])) {
      return 3;
    }
    if (_hasAny(text, [
      'profile',
      'photo',
      'phone',
      'car',
      'vehicle',
      'profil',
      'picture',
      'log out',
      'logout',
      'sign out'
    ])) {
      return 4;
    }
    if (_hasAny(text, ['find', 'search', 'destination', 'filter', 'ride', 'trajet', 'chercher', 'trouver'])) {
      return 0;
    }
    return null;
  }

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
                itemCount: _messages.length,
                itemBuilder: (context, index) => _buildMessage(
                  _messages[index],
                  colors,
                ),
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
          colors: [Color(0xFF3347B0), Color(0xFF6854D9)],
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

  Widget _buildMessage(_ChatMessage message, ColorScheme colors) {
    final isUser = message.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: colors.primaryContainer,
              child: Icon(Icons.auto_awesome, size: 17, color: colors.primary),
            ),
            const SizedBox(width: 8),
          ],
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
                  Text(
                    message.text,
                    style: TextStyle(
                      color: isUser ? colors.onPrimary : colors.onSurface,
                      height: 1.4,
                      fontSize: 13,
                    ),
                  ),
                  if (message.destination != null) ...[
                    const SizedBox(height: 8),
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
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: context.tr('chat_hint'),
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
              onPressed: _send,
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
