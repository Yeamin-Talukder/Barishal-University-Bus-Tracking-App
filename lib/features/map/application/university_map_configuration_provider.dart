import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/university_map_configuration.dart';

/// The map configuration in use.
///
/// Everything that needs the university's position or the offline coverage
/// reads it from here, so a later release can swap in a remotely managed
/// configuration by overriding this one provider.
final universityMapConfigurationProvider = Provider<UniversityMapConfiguration>(
  (ref) => UniversityMapConfiguration.barishal,
);
