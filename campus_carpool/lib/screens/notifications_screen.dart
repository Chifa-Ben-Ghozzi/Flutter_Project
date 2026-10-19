import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../l10n.dart';
import '../models.dart';
import '../providers/notifications_provider.dart';
import '../widgets.dart';
import 'ride_details_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  // AnimatedList : les notifications apparaissent une par une
  final listKey = GlobalKey<AnimatedListState>();
  final items = <AppNotification>[];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    List<AppNotification> fresh = [];
    final ok = await guard(context, () async => fresh = await Api.notifications());
    if (!mounted) return;
    // Vide la liste animée puis insère les éléments avec un léger décalage
    for (var i = items.length - 1; i >= 0; i--) {
      listKey.currentState?.removeItem(i, (_, __) => const SizedBox(), duration: Duration.zero);
    }
    items.clear();
    setState(() => loading = false);
    if (!ok) return;
    for (final n in fresh) {
      await Future.delayed(const Duration(milliseconds: 40));
      if (!mounted) return;
      items.add(n);
      listKey.currentState?.insertItem(items.length - 1, duration: const Duration(milliseconds: 300));
    }
    if (mounted) setState(() {});
    if (mounted) context.read<NotificationsProvider>().markAllRead(); // ouvrir = tout marquer comme lu
  }

  String ago(String iso) {
    final d = DateTime.now().difference(DateTime.parse(iso).toLocal());
    if (d.inMinutes < 1) return context.tr('ago_now');
    if (d.inHours < 1) return context.tr('ago_min', {'n': d.inMinutes});
    if (d.inDays < 1) return context.tr('ago_hours', {'n': d.inHours});
    if (d.inDays < 7) return context.tr('ago_days', {'n': d.inDays});
    return iso.substring(0, 10);
  }

  Widget tile(AppNotification n, Animation<double> anim) {
    final l10n = context.watch<L10n>();
    final unread = !n.read;
    final color = notifColor(n.type);
    return SizeTransition(
      sizeFactor: anim,
      child: FadeTransition(
        opacity: anim,
        child: Column(children: [
          ListTile(
            tileColor: unread ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.07) : null,
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(notifIcon(n.type), color: color),
            ),
            title: Text(notifTitle(n, l10n), style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.normal)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(notifBody(n, l10n)),
              Text(ago(n.createdAt), style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
            isThreeLine: true,
            onTap: n.rideId == null ? null : () => openRide(context, n.rideId!),
          ),
          const Divider(height: 1),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('notifications'))),
      body: loading
          ? const SkeletonList()
          : RefreshIndicator(
              onRefresh: load,
              child: Stack(children: [
                AnimatedList(
                  key: listKey,
                  physics: const AlwaysScrollableScrollPhysics(),
                  initialItemCount: items.length,
                  itemBuilder: (_, i, anim) => tile(items[i], anim),
                ),
                if (items.isEmpty) EmptyState(Icons.notifications_none, context.tr('no_notifications')),
              ]),
            ),
    );
  }
}
