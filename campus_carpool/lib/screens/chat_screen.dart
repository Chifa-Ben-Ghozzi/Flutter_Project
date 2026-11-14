import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n.dart';
import '../models.dart';
import '../repositories/chat_repository.dart';
import '../routes.dart';
import '../services/firestore_service.dart';
import '../widgets.dart';
import 'ride_details_screen.dart';

/// Ouvre la conversation d'une réservation (route nommée '/chat' avec l'id de la réservation).
Future<void> openChat(BuildContext c, String bookingId) => Navigator.pushNamed(c, AppRoutes.chat, arguments: bookingId);

/// Bouton « Message » des écrans de trajet.
class MessageButton extends StatelessWidget {
  final String bookingId;
  const MessageButton(this.bookingId, {super.key});
  @override
  Widget build(BuildContext context) => FilledButton.tonalIcon(
        onPressed: () => openChat(context, bookingId),
        icon: const Icon(Icons.chat_bubble_outline),
        label: Text(context.tr('msg_send_message')),
      );
}

/// Messagerie en temps réel entre le conducteur et un passager.
/// Les messages arrivent en direct (StreamBuilder sur Firestore) et sont marqués lus à l'affichage.
class ChatScreen extends StatefulWidget {
  final String bookingId;
  const ChatScreen({super.key, required this.bookingId});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final input = TextEditingController();
  late final Stream<List<ChatMessage>> messages = ChatRepository.watch(widget.bookingId);
  ChatInfo? info;
  bool loading = true;
  bool sending = false;
  final _marked = <String>{}; // messages déjà marqués lus (évite de renvoyer la même écriture)

  String get me => FirestoreService.uid ?? '';

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> load() async {
    await guard(context, () async => info = await ChatRepository.info(widget.bookingId));
    if (mounted) setState(() => loading = false);
  }

  Future<void> send([String? quick]) async {
    final text = (quick ?? input.text).trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    if (quick == null) input.clear();
    final ok = await guard(context, () => ChatRepository.send(widget.bookingId, text));
    if (!ok && quick == null) input.text = text; // on ne perd pas le texte en cas d'erreur
    if (mounted) setState(() => sending = false);
  }

  /// Les messages reçus non lus sont marqués lus dès qu'ils s'affichent.
  void markRead(List<ChatMessage> list) {
    final fresh = list.where((m) => m.to == me && !m.read && !_marked.contains(m.id)).map((m) => m.id).toList();
    if (fresh.isEmpty) return;
    _marked.addAll(fresh);
    ChatRepository.markRead(widget.bookingId).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final i = info;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: i == null
            ? Text(context.tr('messages'))
            : Row(children: [
                avatar(i.other, radius: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(i.other.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17)),
                    Text(
                      '${i.ride.route} · ${friendlyDate(context, i.ride.dateTime)} ${i.ride.time}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ]),
                ),
              ]),
        actions: [
          if (i != null)
            IconButton(
              tooltip: context.tr('msg_view_ride'),
              onPressed: () => openRide(context, i.ride.id),
              icon: const Icon(Icons.directions_car_outlined),
            ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: StreamBuilder<List<ChatMessage>>(
            stream: messages,
            builder: (context, snap) {
              if (snap.hasError) return EmptyState(Icons.cloud_off, context.tr('err_server'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final list = snap.data!;
              markRead(list);
              if (list.isEmpty) return EmptyState(Icons.forum_outlined, context.tr('msg_empty'));
              return bubbles(list);
            },
          ),
        ),
        if (!loading && i != null) i.open ? composer(i) : closedBanner(),
      ]),
    );
  }

  /// Liste inversée : le dernier message reste en bas, au-dessus du champ de saisie.
  Widget bubbles(List<ChatMessage> list) {
    final lastMineRead = list.lastIndexWhere((m) => m.from == me && m.read);
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      itemCount: list.length,
      itemBuilder: (_, k) {
        final idx = list.length - 1 - k;
        final m = list[idx];
        final newDay = idx == 0 || !DateUtils.isSameDay(list[idx - 1].createdAt, m.createdAt);
        return Column(children: [
          if (newDay)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                friendlyDate(context, m.createdAt),
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          _Bubble(m, mine: m.from == me, seen: idx == lastMineRead),
        ]);
      },
    );
  }

  Widget composer(ChatInfo i) {
    final quick = i.iAmDriver
        ? ['msg_q_meet', 'msg_q_onway', 'msg_q_here', 'msg_q_thanks']
        : ['msg_q_where', 'msg_q_late', 'msg_q_here', 'msg_q_thanks'];
    return SafeArea(
      top: false,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Réponses rapides : un message courant en un geste
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: quick.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, k) => ActionChip(
              label: Text(context.tr(quick[k])),
              onPressed: sending ? null : () => send(context.tr(quick[k])),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                controller: input,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [LengthLimitingTextInputFormatter(ChatRepository.maxLength)],
                onSubmitted: (_) => send(),
                decoration: InputDecoration(
                  hintText: context.tr('msg_hint'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  enabledBorder:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              tooltip: context.tr('send'),
              onPressed: sending ? null : send,
              icon: const Icon(Icons.send_rounded),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget closedBanner() {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        color: scheme.surfaceContainerHighest,
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(Icons.lock_outline, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(context.tr('msg_closed'), style: TextStyle(color: scheme.onSurfaceVariant))),
        ]),
      ),
    );
  }
}

/// Une bulle de message : à droite et colorée pour mes messages, à gauche pour ceux de l'autre.
class _Bubble extends StatelessWidget {
  final ChatMessage m;
  final bool mine;
  final bool seen;
  const _Bubble(this.m, {required this.mine, required this.seen});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = mine ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = mine ? scheme.onPrimary : scheme.onSurface;
    const r = Radius.circular(18);
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.fromLTRB(14, 9, 14, 7),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadiusDirectional.only(
                topStart: r,
                topEnd: r,
                bottomStart: mine ? r : const Radius.circular(4),
                bottomEnd: mine ? const Radius.circular(4) : r,
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(m.text, style: TextStyle(color: fg, fontSize: 15)),
              const SizedBox(height: 2),
              Text(
                '${two(m.createdAt.hour)}:${two(m.createdAt.minute)}',
                style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 11),
              ),
            ]),
          ),
          if (seen)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, right: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.done_all, size: 14, color: scheme.primary),
                const SizedBox(width: 3),
                Text(context.tr('msg_seen'), style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              ]),
            ),
        ]),
      ),
    );
  }
}
