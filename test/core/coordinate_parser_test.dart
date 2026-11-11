import 'package:bu_bus_tracker/core/utils/coordinate_parser.dart';
import 'package:bu_bus_tracker/data/models/geo_point.dart';
import 'package:flutter_test/flutter_test.dart';

void _expectPoint(String input, double latitude, double longitude) {
  final point = parseCoordinates(input);
  expect(point, isNotNull, reason: input);
  expect(point!.latitude, closeTo(latitude, 1e-6), reason: input);
  expect(point.longitude, closeTo(longitude, 1e-6), reason: input);
}

void main() {
  group('parseCoordinates', () {
    test('reads what Google Maps copies: latitude, longitude', () {
      _expectPoint('22.690260, 90.359400', 22.69026, 90.3594);
      _expectPoint('22.690260,90.359400', 22.69026, 90.3594);
      _expectPoint('  (22.69026, 90.3594)  ', 22.69026, 90.3594);
      _expectPoint('22.69026 90.3594', 22.69026, 90.3594);
      _expectPoint('22, 90', 22, 90);
    });

    test('reads negative values and hemisphere letters', () {
      _expectPoint('-33.8688, 151.2093', -33.8688, 151.2093);
      _expectPoint('33.8688° S, 151.2093° E', -33.8688, 151.2093);
      _expectPoint('40.7128 N, 74.0060 W', 40.7128, -74.0060);
    });

    test("reads the app's own way of writing a position", () {
      _expectPoint('22.69026° N, 90.35940° E', 22.69026, 90.3594);
    });

    test('reads degrees, minutes and seconds', () {
      _expectPoint('22°41\'24.9"N 90°21\'33.8"E', 22.690250, 90.359389);
      _expectPoint('22°41′24.9″N, 90°21′33.8″E', 22.690250, 90.359389);
      // Longitude written first.
      _expectPoint('90°21\'33.8"E 22°41\'24.9"N', 22.690250, 90.359389);
    });

    test('reads a full Google Maps link', () {
      _expectPoint(
        'https://www.google.com/maps/place/Nuria+Ideal+School/'
        '@22.6901,90.3581,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2'
        '!3d22.690260!4d90.359400!16s',
        22.69026,
        90.3594,
      );
      _expectPoint(
        'https://www.google.com/maps/@22.6901,90.3581,17z',
        22.6901,
        90.3581,
      );
      _expectPoint(
        'https://maps.google.com/?q=22.690260,90.359400',
        22.69026,
        90.3594,
      );
      _expectPoint(
        'https://www.google.com/maps/search/?api=1&query=22.690260%2C90.359400',
        22.69026,
        90.3594,
      );
    });

    test('prefers the place pin over the centre of the map in a link', () {
      _expectPoint(
        'https://www.google.com/maps/place/X/@22.1,90.1,17z/data=!3d22.5!4d90.5',
        22.5,
        90.5,
      );
    });

    test('returns nothing rather than guessing', () {
      for (final input in [
        '',
        '   ',
        'Nuria School',
        '22.690260',
        '22.690260, north',
        '122.5, 90.3', // latitude out of range
        '22.5, 190.3', // longitude out of range
        '22.5, 90.3, 14.2',
        'https://maps.app.goo.gl/AbCdEf123456',
        'call 01712 345678',
        '100% sure',
      ]) {
        expect(parseCoordinates(input), isNull, reason: input);
      }
    });
  });

  group('coordinatesToText', () {
    test('writes six decimals, latitude first', () {
      expect(
        coordinatesToText(const GeoPoint(22.69026, 90.3594)),
        '22.690260, 90.359400',
      );
    });

    test('is read back as the same position', () {
      const point = GeoPoint(22.677041, 90.349463);

      final back = parseCoordinates(coordinatesToText(point))!;

      expect(back.latitude, closeTo(point.latitude, 1e-6));
      expect(back.longitude, closeTo(point.longitude, 1e-6));
    });
  });
}
