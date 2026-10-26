package app.mosh.mosh

import android.graphics.Color
import android.view.View
import android.view.ViewGroup

/** Covers the previous Flutter surface until a checked protected frame paints. */
internal class MoshAccessShield {
    private var activity: MainActivity? = null
    private var view: View? = null
    var generation = 0L
        private set

    fun attach(activity: MainActivity) { this.activity = activity }

    fun detach(activity: MainActivity) {
        if (this.activity !== activity) return
        remove()
        this.activity = null
    }

    fun protect() {
        generation++
        val activity = activity ?: return
        if (view != null) return
        view = View(activity).apply { setBackgroundColor(Color.BLACK) }
        activity.addContentView(view, ViewGroup.LayoutParams(-1, -1))
    }

    fun ready(generation: Long?) {
        if (generation != this.generation) return
        remove()
    }

    private fun remove() {
        view?.let { (it.parent as? ViewGroup)?.removeView(it) }
        view = null
    }
}
