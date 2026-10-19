import 'package:campus_carpool/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Trajet', () {
    test('lieu obligatoire, 2 caractères minimum', () {
      expect(Validators.place(''), 'v_required');
      expect(Validators.place('  '), 'v_required');
      expect(Validators.place('A'), 'v_min2');
      expect(Validators.place('Ariana'), isNull);
    });

    test('destination différente du départ (sans tenir compte de la casse)', () {
      expect(Validators.destination('tunis ', 'Tunis'), 'v_same_place');
      expect(Validators.destination('La Marsa', 'Tunis'), isNull);
      expect(Validators.destination('', 'Tunis'), 'v_required');
    });

    test('date et heure dans le futur', () {
      final now = DateTime(2026, 5, 10, 12, 0);
      expect(Validators.dateTime(null, 9, 0, now: now), 'v_pick_date');
      expect(Validators.dateTime(DateTime(2026, 5, 10), null, null, now: now), 'v_pick_time');
      expect(Validators.dateTime(DateTime(2026, 5, 10), 11, 59, now: now), 'v_time_past');
      expect(Validators.dateTime(DateTime(2026, 5, 10), 12, 30, now: now), isNull);
    });

    test('places entre 1 et 8', () {
      expect(Validators.seats('abc'), 'v_integer');
      expect(Validators.seats('0'), 'v_seats_range');
      expect(Validators.seats('9'), 'v_seats_range');
      expect(Validators.seats('4'), isNull);
    });

    test('prix : nombre positif, virgule acceptée', () {
      expect(Validators.price(''), 'v_number');
      expect(Validators.price('-1'), 'v_positive');
      expect(Validators.price('500'), 'v_price_high');
      expect(Validators.price('4,5'), isNull);
      expect(Validators.parsePrice('4,5'), 4.5);
    });
  });

  group('Profil', () {
    test('nom obligatoire', () {
      expect(Validators.name(''), 'v_name_required');
      expect(Validators.name('Sami'), isNull);
    });

    test('téléphone facultatif : 8 chiffres ou international', () {
      expect(Validators.phone(''), isNull);
      expect(Validators.phone('22 123 456'), isNull);
      expect(Validators.phone('+21622123456'), isNull);
      expect(Validators.phone('12345'), 'v_phone');
      expect(Validators.phone('abcdefgh'), 'v_phone');
    });

    test('plaque obligatoire si une voiture est indiquée (et inversement)', () {
      expect(Validators.plate('', 'Clio'), 'v_plate_required');
      expect(Validators.plate('215 TU 4521', ''), 'v_model_required');
      expect(Validators.plate('12', 'Clio'), 'v_plate_short');
      expect(Validators.plate('215 TU 4521', 'Clio'), isNull);
      expect(Validators.plate('', ''), isNull);
    });
  });
}
