import '../models/bus.dart';
import 'bus_repository.dart';
import 'live_tracking_repository.dart';

/// The driver the tracking rules should accept for [bus]: its assigned
/// driver while it is in service, nobody otherwise.
String? trackingDriverOf(Bus bus) => bus.isActive ? bus.driverUid : null;

/// A bus list that also tells the tracking database who drives each bus.
///
/// The Realtime Database enforces who may start a trip, but it cannot see
/// the bus list in Firestore. Every change an admin makes to a bus is
/// therefore copied across here.
class MirroringBusRepository implements BusRepository {
  const MirroringBusRepository(this._inner, this._access);

  final BusRepository _inner;
  final TrackingAccess _access;

  @override
  Stream<List<Bus>> watchBuses() => _inner.watchBuses();

  @override
  Future<String> saveBus(Bus bus) async {
    final id = await _inner.saveBus(bus);
    await _mirror({id: trackingDriverOf(bus)});
    return id;
  }

  @override
  Future<void> addAll(List<Bus> buses) async {
    if (buses.every((bus) => trackingDriverOf(bus) == null)) {
      // Nobody drives them yet, so there is nothing to copy across.
      return _inner.addAll(buses);
    }
    for (final bus in buses) {
      await saveBus(bus);
    }
  }

  @override
  Future<void> deleteBus(String id) async {
    await _inner.deleteBus(id);
    await _mirror({id: null});
  }

  Future<void> _mirror(Map<String, String?> drivers) async {
    try {
      await _access.setBusDrivers(drivers);
    } on TrackingFailure catch (failure) {
      throw BusWriteFailure(failure.message);
    }
  }
}
