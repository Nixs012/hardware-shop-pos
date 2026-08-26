import '../models/sale.dart';

class SyncService {
  // Offline queue + conflict resolution (see pos-domain-rules skill)
  // - Conflict rule for stock quantity: sum decrements
  // - Never silently drop a sale record
  
  Future<void> queueSaleOffline(Sale sale) async {
    // Save sale to local DB (e.g., SQLite/Hive)
    // Decrement stock locally (optimistic)
  }

  Future<void> syncSalesWithServer() async {
    // Send all offline sales to Firestore
    // Resolve stock decrement conflicts by summing them on the server side
    // If conflict can't be resolved, surface in "Needs Review"
  }
}
