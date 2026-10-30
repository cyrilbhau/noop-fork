package com.noop.ble

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BackfillIdlePolicyTest {
    @Test fun onlyIntactHistoryExtendsDeadline() {
        // Literal stdout from the standalone Swift policy oracle over all 256 wire types.
        val accepted = (0..255).filter { BackfillIdlePolicy.shouldExtendTimeout(it, true) }
        val rejected = (0..255).filter { BackfillIdlePolicy.shouldExtendTimeout(it, false) }
        assertEquals("47,49,52,56", accepted.joinToString(","))
        assertEquals("", rejected.joinToString(","))
    }

    @Test fun liveChatterAfterHistoryCannotKeepTheSyncAlive() {
        var deadline = 60
        if (BackfillIdlePolicy.shouldExtendTimeout(47, true)) deadline = 30 + 60
        for (second in 31..900) {
            for (type in listOf(40, 43, 48, 50)) {
                if (BackfillIdlePolicy.shouldExtendTimeout(type, true)) deadline = second + 60
            }
        }
        assertEquals(90, deadline)
    }

    @Test fun slowHistoryAndConsoleChunkBoundariesKeepTheirAllowance() {
        var deadline = 60
        for (second in 59..1180 step 59) {
            assertTrue(second < deadline)
            val type = if (second % 118 == 0) 49 else 47
            if (BackfillIdlePolicy.shouldExtendTimeout(type, true)) deadline = second + 60
        }
        assertEquals(1240, deadline)
    }
}
