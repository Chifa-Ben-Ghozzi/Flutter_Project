import 'package:flutter/material.dart';
import 'search_screen.dart';
import 'post_ride_screen.dart';
import 'my_rides_screen.dart';
import 'my_bookings_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const SearchScreen(),
      const PostRideScreen(),
      const MyRidesScreen(),
      const MyBookingsScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      body: SafeArea(child: pages[index]), // recréé à chaque changement d'onglet => données rafraîchies
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.search), label: 'Chercher'),
          NavigationDestination(icon: Icon(Icons.add_circle_outline), label: 'Publier'),
          NavigationDestination(icon: Icon(Icons.directions_car), label: 'Mes trajets'),
          NavigationDestination(icon: Icon(Icons.event_seat), label: 'Réservations'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}
