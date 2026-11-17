/// One bank transfer MOJUD made to the driver: their share of [rides] paid
/// trips, with the bank's reference (UTR) to match it on a statement.
///
/// A pure domain type; [Payout.tryParse] reads one entry of the backend's
/// `GET /driver/payouts`.
class Payout {
  const Payout({
    required this.id,
    required this.amountPaise,
    required this.rides,
    required this.reference,
    required this.createdAt,
  });

  final String id;
  final int amountPaise;
  final int rides;

  /// The bank's transfer reference (UTR).
  final String reference;

  /// When MOJUD recorded the transfer.
  final DateTime createdAt;

  int get rupees => (amountPaise / 100).round();

  /// Parses one payout, or null for one this app version can't read.
  static Payout? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final amount = json['amountPaise'];
    final createdAt = json['createdAt'];
    final at = createdAt is String ? DateTime.tryParse(createdAt) : null;
    if (id is! String || amount is! num || at == null) return null;
    final reference = json['reference'];
    return Payout(
      id: id,
      amountPaise: amount.toInt(),
      rides: (json['rides'] as num?)?.toInt() ?? 0,
      reference: reference is String ? reference.trim() : '',
      createdAt: at.toLocal(),
    );
  }
}
