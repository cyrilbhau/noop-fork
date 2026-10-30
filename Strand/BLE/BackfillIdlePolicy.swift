/// Activity that may extend an existing historical-offload idle deadline. Routing and liveness are
/// separate: EVENT and CONSOLE_LOGS must still reach the Backfiller, but both can also arrive live
/// after the historical stream has stopped. Letting that chatter renew the deadline prevents a
/// WHOOP 4.0 that omits HISTORY_COMPLETE from ever leaving its syncing state.
///
/// History records and chunk boundaries keep the full idle allowance. In particular, metadata still
/// renews it while draining console-only chunks. A rejected frame never proves progress; it still
/// follows the existing archival path. This policy neither acknowledges nor discards any frame.
/// Type 52 is included for parity with Android's existing historical IMU route; Swift's current
/// offload routing does not deliver that type and is deliberately unchanged here.
/// Kotlin twin: com.noop.ble.BackfillIdlePolicy.
enum BackfillIdlePolicy {
    static func shouldExtendTimeout(packetType: Int, integrityOK: Bool) -> Bool {
        guard integrityOK else { return false }
        switch packetType {
        case 47, 49, 52, 56: // historical data, metadata, historical IMU, puffin metadata
            return true
        default:
            return false
        }
    }
}
