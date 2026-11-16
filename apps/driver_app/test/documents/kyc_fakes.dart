import 'package:driver_app/features/documents/data/kyc_status_store.dart';
import 'package:driver_app/features/documents/domain/driver_kyc.dart';

/// An in-memory [KycStatusStore], keyed by driver like the real one.
class MemoryKycStatusStore implements KycStatusStore {
  MemoryKycStatusStore([this.driverId, this.status]);

  String? driverId;
  KycStatus? status;
  int writes = 0;

  @override
  Future<KycStatus?> read(String driverId) async =>
      driverId == this.driverId ? status : null;

  @override
  Future<void> write(String driverId, KycStatus status) async {
    writes++;
    this.driverId = driverId;
    this.status = status;
  }
}
