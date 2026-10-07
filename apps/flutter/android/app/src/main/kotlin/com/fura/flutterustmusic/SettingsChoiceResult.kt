package com.fura.flutterustmusic

/** A dialog owns exactly one result. Old dismiss callbacks cannot finish a new request. */
internal class SettingsChoiceResult {
    private var pending: Pending? = null
    private data class Pending(val id: Int, val finish: (Int?) -> Unit, val fail: (() -> Unit)?)

    fun begin(id: Int, fail: (() -> Unit)? = null, finish: (Int?) -> Unit): Boolean {
        if (pending != null) return false
        pending = Pending(id, finish, fail)
        return true
    }

    fun complete(id: Int, value: Int?) {
        val current = pending ?: return
        if (current.id != id) return
        pending = null
        current.finish(value)
    }

    fun cancel() {
        pending?.let { complete(it.id, null) }
    }

    fun fail(id: Int) {
        val current = pending ?: return
        if (current.id != id) return
        pending = null
        if (current.fail != null) current.fail.invoke() else current.finish(null)
    }
}
