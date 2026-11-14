import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n.dart';
import '../providers/chat_provider.dart';
import '../providers/notifications_provider.dart';
import '../routes.dart';
import '../theme.dart';
import '../widgets.dart';
import 'help_chat_screen.dart';
import 'my_bookings_screen.dart';
import 'my_rides_screen.dart';
import 'post_ride_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';
import '../services/network_status.dart';

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
    final unreadMessages = context.watch<ChatProvider>().unread;
    final scheme = Theme.of(context).colorScheme;

    // Bouton rond de la barre du haut, avec un badge de non-lus
    Widget action(
            {required String tooltip, required VoidCallback onPressed, required IconData icon, required int count}) =>
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.card(scheme),
              side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            icon: Badge(
              isLabelVisible: count > 0,
              label: Text(count > 9 ? '9+' : '$count'),
              child: Icon(icon, size: 22),
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Row(children: [
          BrandMark(),
          SizedBox(width: 10),
          Text('Campus Carpool', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.4)),
        ]),
        actions: [
          action(
            tooltip: context.tr('messages'),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.messages),
            icon: unreadMessages > 0 ? Icons.forum : Icons.forum_outlined,
            count: unreadMessages,
          ),
          action(
            tooltip: context.tr('notifications'),
            onPressed: openNotifications,
            icon: unread > 0 ? Icons.notifications_active : Icons.notifications_none,
            count: unread,
          ),
          const SizedBox(width: 12),
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
      floatingActionButton: index != 1 && index != 4 ? _AiButton(onPressed: openHelpChat) : null,
      // Barre d'onglets blanche, séparée du contenu par un filet ; icône pleine sur l'onglet actif
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4))),
        ),
        child: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => setState(() => index = i),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.search_rounded),
              selectedIcon: const Icon(Icons.travel_explore_rounded),
              label: context.tr('tab_search'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.add_circle_outline_rounded),
              selectedIcon: const Icon(Icons.add_circle_rounded),
              label: context.tr('tab_post'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.directions_car_outlined),
              selectedIcon: const Icon(Icons.directions_car_filled_rounded),
              label: context.tr('tab_my_rides'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.event_seat_outlined),
              selectedIcon: const Icon(Icons.event_seat_rounded),
              label: context.tr('tab_bookings'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline_rounded),
              selectedIcon: const Icon(Icons.person_rounded),
              label: context.tr('tab_profile'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bouton de l'assistant : rond, au dégradé de la marque, avec une ombre colorée.
class _AiButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _AiButton({required this.onPressed});
  @override
  Widget build(BuildContext context) => Tooltip(
        message: context.tr('ai_help'),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppTheme.brandGradient,
            boxShadow: [
              BoxShadow(color: AppTheme.violet.withValues(alpha: 0.4), blurRadius: 18, offset: const Offset(0, 8)),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: const SizedBox(
                width: 58,
                height: 58,
                child: Icon(Icons.auto_awesome, color: Colors.white),
              ),
            ),
          ),
        ),
      );
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
