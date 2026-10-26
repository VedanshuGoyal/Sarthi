/// A UPI checkout the server opened at the payment gateway for one completed
/// ride: what the app hands PhonePe's SDK to show the payment page.
///
/// A pure domain type; [PaymentCheckout.tryParse] reads the backend's
/// `POST /me/bookings/{id}/payment` reply.
class PaymentCheckout {
  const PaymentCheckout({
    required this.environment,
    required this.merchantId,
    required this.orderId,
    required this.token,
    required this.amountPaise,
    this.merchantOrderId,
  });

  /// `SANDBOX` or `PRODUCTION`, as the SDK names it.
  final String environment;
  final String merchantId;

  /// The gateway's order id and the token that opens it.
  final String orderId;
  final String token;
  final int amountPaise;

  /// The server's name for the order, for support.
  final String? merchantOrderId;

  int get amountRupees => (amountPaise / 100).round();

  static PaymentCheckout? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final environment = json['environment'];
    final merchantId = json['merchantId'];
    final orderId = json['orderId'];
    final token = json['token'];
    if (environment is! String ||
        merchantId is! String ||
        orderId is! String ||
        token is! String ||
        orderId.isEmpty ||
        token.isEmpty) {
      return null;
    }
    return PaymentCheckout(
      environment: environment,
      merchantId: merchantId,
      orderId: orderId,
      token: token,
      amountPaise: (json['amountPaise'] as num?)?.toInt() ?? 0,
      merchantOrderId: json['merchantOrderId'] as String?,
    );
  }
}
