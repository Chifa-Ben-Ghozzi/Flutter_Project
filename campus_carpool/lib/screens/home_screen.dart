import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../l10n.dart';
import '../providers/notifications_provider.dart';
import '../routes.dart';
import 'help_chat_screen.dart';
import 'my_bookings_screen.dart';
import 'my_rides_screen.dart';
import 'post_ride_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int index = 0;
  // Change au retour des notifications => l'onglet courant se recharge
  int refreshKey = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) context.read<NotificationsProvider>().refresh();
  }

  Future<void> openNotifications() async {
    await Navigator.pushNamed(context, AppRoutes.notifications);
    if (mounted) setState(() => refreshKey++);
  }

  void openHelpChat() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: FractionallySizedBox(
          heightFactor: 0.92,
          child: HelpChatScreen(
            onNavigate: (destination) {
              setState(() => index = destination);
              Navigator.pop(context);
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const pages = <Widget>[
      SearchScreen(),
      PostRideScreen(),
      MyRidesScreen(),
      MyBookingsScreen(),
      ProfileScreen(),
    ];
    final unread = context.watch<NotificationsProvider>().unread;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Campus Carpool', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: context.tr('notifications'),
            onPressed: openNotifications,
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 9 ? '9+' : '$unread'),
              child: Icon(unread > 0 ? Icons.notifications_active : Icons.notifications_none),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          const _OfflineBanner(),
          Expanded(
            // Fondu entre les onglets ; chaque onglet est recréé => données rafraîchies
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: KeyedSubtree(key: ValueKey('$index-$refreshKey'), child: pages[index]),
            ),
          ),
        ]),
      ),
      // Caché sur les formulaires (Publier, Profil) pour ne pas masquer leurs boutons
      floatingActionButton: index != 1 && index != 4
          ? FloatingActionButton.extended(
              onPressed: openHelpChat,
              icon: const Icon(Icons.auto_awesome),
              label: Text(context.tr('ai_help')),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.search), label: context.tr('tab_search')),
          NavigationDestination(icon: const Icon(Icons.add_circle_outline), label: context.tr('tab_post')),
          NavigationDestination(icon: const Icon(Icons.directions_car), label: context.tr('tab_my_rides')),
          NavigationDestination(icon: const Icon(Icons.event_seat), label: context.tr('tab_bookings')),
          NavigationDestination(icon: const Icon(Icons.person), label: context.tr('tab_profile')),
        ],
      ),
    );
  }
}

/// Bandeau affiché quand le serveur est injoignable (les listes viennent alors du cache).
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();
  @override
  Widget build(BuildContext context) {
    final online = context.watch<NetworkStatus>().online;
    final scheme = Theme.of(context).colorScheme;
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      child: online
          ? const SizedBox(width: double.infinity)
          : Material(
              color: scheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(children: [
                  Icon(Icons.cloud_off, size: 18, color: scheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(child: Text(context.tr('offline_banner'), style: TextStyle(color: scheme.onErrorContainer))),
                  TextButton(
                    onPressed: () => context.read<NotificationsProvider>().refresh(),
                    child: Text(context.tr('retry')),
                  ),
                ]),
              ),
            ),
    );
  }
}
