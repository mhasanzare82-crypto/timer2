import 'package:flutter_test/flutter_test.dart';
import 'package:timer/utils/jalali_date_storage.dart';

void main() {
  group('JalaliDateStorage', () {
    test('stores a Gregorian runtime date as a Jalali string and round-trips', () {
      final original = DateTime(2024, 3, 20, 14, 5, 6, 7);

      final stored = JalaliDateStorage.encode(original);

      expect(stored, '1403/01/01 14:05:06.007');
      expect(JalaliDateStorage.decode(stored), original);
    });

    test('reads legacy epoch-millisecond values for migration and old backups', () {
      final original = DateTime(2024, 3, 20, 14, 5, 6, 7);

      expect(
        JalaliDateStorage.decode(original.millisecondsSinceEpoch),
        original,
      );
    });
  });
}
