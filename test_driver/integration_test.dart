// Host-side entry point for running the on-device tests with `flutter drive`,
// which (unlike `flutter test`) can use a small profile build.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
