import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:phonepe_payment_sdk/phonepe_payment_sdk.dart';

import '../domain/payment_checkout.dart';

/// How the payment page closed, as the gateway's SDK reports it. Only the
/// server's check with the gateway decides whether the ride is paid; this
/// just says whether to expect it.
enum CheckoutOutcome {
  /// The customer finished paying.
  success,

  /// The payment failed or was declined.
  failure,

  /// The customer backed out before finishing.
  interrupted,
}

/// Opens the payment gateway's UPI checkout. A data-layer seam over the
/// PhonePe SDK, so view models and tests never touch the plugin.
abstract interface class UpiCheckout {
  /// Shows the payment page for [checkout]. [flowId] ties the SDK's logs to
  /// this customer. Throws [UpiCheckoutException] if it can't open.
  Future<CheckoutOutcome> open(
    PaymentCheckout checkout, {
    required String flowId,
  });
}

/// Raised when the payment page couldn't be opened at all.
class UpiCheckoutException implements Exception {
  const UpiCheckoutException(this.message);
  final String message;
  @override
  String toString() => 'UpiCheckoutException: $message';
}

/// [UpiCheckout] over PhonePe's Standard Checkout SDK
/// (`phonepe_payment_sdk`): init with the merchant and environment the
/// server named, then start the transaction with the order's token.
class PhonePeUpiCheckout implements UpiCheckout {
  PhonePeUpiCheckout();

  /// The merchant/environment the SDK was last initialised for.
  String? _initialisedFor;

  @override
  Future<CheckoutOutcome> open(
    PaymentCheckout checkout, {
    required String flowId,
  }) async {
    final key = '${checkout.environment}/${checkout.merchantId}';
    try {
      if (_initialisedFor != key) {
        final ok = await PhonePePaymentSdk.init(
          checkout.environment,
          checkout.merchantId,
          _alphanumeric(flowId),
          false,
        );
        if (!ok) {
          throw const UpiCheckoutException("PhonePe couldn't start.");
        }
        _initialisedFor = key;
      }
      final request = jsonEncode({
        'orderId': checkout.orderId,
        'merchantId': checkout.merchantId,
        'token': checkout.token,
        'paymentMode': {'type': 'PAY_PAGE'},
      });
      // The app scheme only matters on iOS; Android returns to the app.
      final result = await PhonePePaymentSdk.startTransaction(request, 'mojud');
      return switch (result?['status']) {
        'SUCCESS' => CheckoutOutcome.success,
        'FAILURE' => CheckoutOutcome.failure,
        _ => CheckoutOutcome.interrupted,
      };
    } on PlatformException catch (e) {
      throw UpiCheckoutException(e.message ?? "PhonePe couldn't open.");
    } on MissingPluginException {
      throw const UpiCheckoutException(
        'Paying by UPI works in the Android app.',
      );
    }
  }

  /// The SDK takes letters and digits only.
  static String _alphanumeric(String s) {
    final cleaned = s.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    return cleaned.isEmpty ? 'mojud' : cleaned;
  }
}
