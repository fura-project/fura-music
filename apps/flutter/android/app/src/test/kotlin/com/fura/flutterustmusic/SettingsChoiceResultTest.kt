package com.fura.flutterustmusic

import org.junit.Assert.*
import org.junit.Test

class SettingsChoiceResultTest {
    @Test fun showFailureIsTruthfulAndCannotCompleteTwice() {
        val results = SettingsChoiceResult()
        var failures = 0
        var successes = 0
        assertTrue(results.begin(1, { failures++ }) { successes++ })
        results.fail(1)
        results.cancel()
        results.complete(1, 0)
        assertEquals(1, failures)
        assertEquals(0, successes)
        assertTrue(results.begin(2) { successes++ })
        results.fail(1)
        results.complete(2, 1)
        assertEquals(1, successes)
    }
    @Test fun completionIsExactlyOnceAndOldDismissCannotCompleteNewDialog() {
        val results = SettingsChoiceResult()
        val first = mutableListOf<Int?>()
        val second = mutableListOf<Int?>()
        assertTrue(results.begin(1) { first.add(it) })
        assertFalse(results.begin(2) { second.add(it) })
        results.complete(1, 2)
        results.complete(1, null)
        assertEquals(listOf(2), first)
        assertTrue(results.begin(2) { second.add(it) })
        results.complete(1, 0)
        assertTrue(second.isEmpty())
        results.complete(2, null)
        assertEquals(listOf(null), second)
    }

    @Test fun pauseDetachDisposalCancelOnlyOnceAndAllowNextRequest() {
        val results = SettingsChoiceResult()
        val completed = mutableListOf<Int?>()
        assertTrue(results.begin(1) { completed.add(it) })
        results.cancel()
        results.cancel()
        results.complete(1, 1)
        assertEquals(listOf(null), completed)
        assertTrue(results.begin(2) { completed.add(it) })
        results.complete(2, 0)
        assertEquals(listOf(null, 0), completed)
    }
}
