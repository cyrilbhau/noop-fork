package com.noop.ble

/**
 * Twin of Swift BackfillIdlePolicy. EVENT and CONSOLE_LOGS still route into the offload, but they
 * can also arrive live after history stops, so they cannot extend its idle deadline. Intact history
 * records and metadata boundaries retain the full allowance, including console-only chunks.
 * Rejected frames still follow the existing archival path; this policy never acknowledges data.
 */
object BackfillIdlePolicy {
    fun shouldExtendTimeout(packetType: Int, integrityOK: Boolean): Boolean {
        if (!integrityOK) return false
        return when (packetType) {
            47, 49, 52, 56 -> true
            else -> false
        }
    }
}
