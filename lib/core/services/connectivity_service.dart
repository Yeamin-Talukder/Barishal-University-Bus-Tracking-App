import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tells whether the device has a network connection.
///
/// This reports whether a network (Wi-Fi, mobile data, Ethernet) is
/// connected, not whether the internet is actually reachable through it.
/// Live tracking will add its own check against the tracking service.
abstract interface class ConnectivityService {
  Future<bool> hasConnection();

  /// Emits whenever the connection comes or goes.
  Stream<bool> get onConnectionChanged;
}

class PlusConnectivityService implements ConnectivityService {
  PlusConnectivityService([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  static bool _isConnected(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);

  @override
  Future<bool> hasConnection() async =>
      _isConnected(await _connectivity.checkConnectivity());

  @override
  Stream<bool> get onConnectionChanged =>
      _connectivity.onConnectivityChanged.map(_isConnected).distinct();
}

final connectivityServiceProvider = Provider<ConnectivityService>(
  (ref) => PlusConnectivityService(),
);

/// Whether the device currently has a network connection.
final hasConnectionProvider = StreamProvider<bool>((ref) async* {
  final service = ref.watch(connectivityServiceProvider);
  yield await service.hasConnection();
  yield* service.onConnectionChanged;
});
