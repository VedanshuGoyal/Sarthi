import 'pickup_location.dart';

/// One planned stop on a Multi-Stop trip: where to go, what to do there, and
/// when to move on.
///
/// The customer writes the plan like a task list for the driver — each stop is
/// an errand ("pick up the parcel from reception") pinned to a [location], with
/// a [departBy] deadline so the whole day stays on schedule.
class TripStop {
  const TripStop({
    required this.location,
    required this.task,
    required this.departBy,
  });

  final PickupLocation location;

  /// What the driver should do at this stop, in the customer's words.
  final String task;

  /// When the driver should leave this stop for the next one.
  final DateTime departBy;

  Map<String, dynamic> toJson() => {
    'location': location.toJson(),
    'task': task,
    'departBy': departBy.toIso8601String(),
  };
}
