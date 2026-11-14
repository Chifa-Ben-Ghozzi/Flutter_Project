import 'package:flutter/material.dart';
import '../l10n.dart';
import '../models.dart';
import '../repositories/chat_repository.dart';
import '../services/firestore_service.dart';
import '../widgets.dart';
import 'chat_screen.dart';

/// Boîte de réception : toutes mes conversations, la plus récente en premier, mises à jour en direct.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});
  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  late final Stream<List<Conversation>> conversations = ChatRepository.conversations();

  String when(DateTime d) =>
      DateUtils.isSameDay(d, DateTime.now()) ? '${two(d.hour)}:${two(d.minute)}' : friendlyDate(context, d);

  @override
  Widget build(BuildContext context) {
    final me = FirestoreService.uid;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('messages'))),
      body: StreamBuilder<List<Conversation>>(
        stream: conversations,
        builder: (context, snap) {
          if (snap.hasError) return EmptyState(Icons.cloud_off, context.tr('err_server'));
          if (!snap.hasData) return const SkeletonList();
          final list = snap.data!;
          if (list.isEmpty) return EmptyState(Icons.forum_outlined, context.tr('msg_no_conversations'));
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
            itemBuilder: (_, i) => FadeSlideIn(index: i, child: tile(list[i], me)),
          );
        },
      ),
    );
  }

  Widget tile(Conversation c, String? me) {
    final scheme = Theme.of(context).colorScheme;
    final unread = c.unread > 0;
    final text = c.last.from == me ? context.tr('msg_you', {'text': c.last.text}) : c.last.text;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: avatar(AppUser(id: c.otherId, name: c.otherName), radius: 24),
      title: Row(children: [
        Expanded(
          child: Text(c.otherName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
        ),
        Text(when(c.last.createdAt),
            style: TextStyle(fontSize: 12, color: unread ? scheme.primary : scheme.onSurfaceVariant)),
      ]),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.route, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: scheme.primary)),
        Row(children: [
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: unread ? scheme.onSurface : null, fontWeight: unread ? FontWeight.w600 : null),
            ),
          ),
          if (unread) Badge(label: Text('${c.unread}'), backgroundColor: scheme.primary),
        ]),
      ]),
      onTap: () => openChat(context, c.bookingId),
    );
  }
}
