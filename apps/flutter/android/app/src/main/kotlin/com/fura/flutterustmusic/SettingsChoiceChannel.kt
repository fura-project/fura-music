package com.fura.flutterustmusic

import android.app.Activity
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.view.ContextThemeWrapper
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import androidx.core.view.ViewCompat
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.color.MaterialColors
import com.google.android.material.radiobutton.MaterialRadioButton
import com.google.android.material.textview.MaterialTextView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Activity-scoped, presentation-only edge. No Settings/Provider/persistence ownership. */
internal class SettingsChoiceChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.fura/settings_choice")
    private val results = SettingsChoiceResult()
    private var dialog: BottomSheetDialog? = null
    private var requestId: Int? = null
    var resumed = false

    init { channel.setMethodCallHandler(::handle) }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "dismiss" -> {
                if (call.argument<Int>("requestId") == requestId) cancel()
                result.success(null)
            }
            "show" -> {
                if (!resumed || activity.isFinishing || activity.isDestroyed) {
                    result.error("unavailable", "Activity is not available", null)
                    return
                }
                val request = parse(call)
                if (request == null) {
                    result.error("invalid_presentation", "Invalid choice presentation", null)
                    return
                }
                if (!results.begin(request.id, { result.error("unavailable", "Native dialog could not be shown", null) }) { result.success(it) }) {
                    result.error("busy", "A Settings choice is already open", null)
                    return
                }
                requestId = request.id
                try { show(request) } catch (error: RuntimeException) {
                    // No exception message/payload enters diagnostics or the bridge.
                    results.fail(request.id)
                    cancel()
                }
            }
            else -> result.notImplemented()
        }
    }

    private data class Option(val label: String, val supporting: String?, val enabled: Boolean)
    private data class Request(val id: Int, val title: String, val options: List<Option>, val selected: Int, val dark: Boolean, val primary: Int?, val footer: String?)

    private fun parse(call: MethodCall): Request? {
        val args = call.arguments as? Map<*, *> ?: return null
        fun text(value: Any?): String? = (value as? String)?.takeIf { it.isNotBlank() && it.length <= 2048 }
        val id = args["requestId"] as? Int ?: return null
        val title = text(args["title"]) ?: return null
        val raw = args["options"] as? List<*> ?: return null
        if (raw.isEmpty() || raw.size > 32) return null
        val options = raw.map { value ->
            val option = value as? Map<*, *> ?: return null
            val label = text(option["label"]) ?: return null
            val supporting = option["supportingText"]
            if (supporting != null && text(supporting) == null) return null
            Option(label, supporting as? String, option["enabled"] as? Boolean ?: return null)
        }
        val selected = args["selectedIndex"] as? Int ?: return null
        if (selected !in options.indices) return null
        val brightness = args["brightness"] as? String ?: return null
        if (brightness !in setOf("light", "dark")) return null
        val footer = args["footer"]
        if (footer != null && text(footer) == null) return null
        return Request(id, title, options, selected, brightness == "dark", (args["primary"] as? Number)?.toInt(), footer as? String)
    }

    private fun show(request: Request) {
        // Dialog-only theme; the Flutter Activity/splash/playback host is unchanged.
        // Explicit uiMode also makes AppCompat honor app-dark while OS is light.
        val configuration = Configuration(activity.resources.configuration)
        configuration.uiMode = (configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
            (if (request.dark) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO)
        val theme = if (request.dark) R.style.SettingsChoiceDark else R.style.SettingsChoiceLight
        val context = ContextThemeWrapper(activity, theme)
        context.applyOverrideConfiguration(configuration)
        // Passing 0 would re-resolve bottomSheetDialogTheme and can replace
        // this explicit app-dark context with the inherited light dialog.
        val sheet = BottomSheetDialog(context, theme)
        dialog = sheet
        sheet.setTitle(request.title)
        var selection: Int? = null
        val content = LinearLayout(sheet.context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(16), dp(16), dp(24))
        }
        val heading = MaterialTextView(sheet.context).apply {
            text = request.title
            setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_TitleLarge)
            setPadding(dp(8), 0, dp(8), dp(16))
            ViewCompat.setAccessibilityHeading(this, true)
        }
        content.addView(heading)
        val onSurface = MaterialColors.getColor(content, com.google.android.material.R.attr.colorOnSurface)
        val primary = request.primary ?: MaterialColors.getColor(content, com.google.android.material.R.attr.colorPrimary)
        for ((index, option) in request.options.withIndex()) {
            val row = LinearLayout(sheet.context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                minimumHeight = dp(56)
                setPadding(0, dp(8), dp(8), dp(8))
                isEnabled = option.enabled
                isFocusable = option.enabled
                val attrs = context.obtainStyledAttributes(intArrayOf(android.R.attr.selectableItemBackground))
                background = attrs.getDrawable(0)
                attrs.recycle()
            }
            val radio = MaterialRadioButton(sheet.context).apply {
                isChecked = index == request.selected
                isEnabled = option.enabled
                isClickable = false
                isFocusable = false
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                buttonTintList = ColorStateList(arrayOf(intArrayOf(-android.R.attr.state_enabled), intArrayOf(android.R.attr.state_checked), intArrayOf()), intArrayOf(androidx.core.graphics.ColorUtils.setAlphaComponent(onSurface, 97), primary, onSurface))
            }
            row.addView(radio)
            val labels = LinearLayout(sheet.context).apply { orientation = LinearLayout.VERTICAL }
            labels.addView(MaterialTextView(sheet.context).apply {
                text = option.label
                setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_BodyLarge)
                isEnabled = option.enabled
            })
            option.supporting?.let { supporting -> labels.addView(MaterialTextView(sheet.context).apply {
                text = supporting
                setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_BodySmall)
            }) }
            row.addView(labels, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            row.contentDescription = listOfNotNull(option.label, option.supporting).joinToString("\n")
            labels.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            // One accessible native radio target per whole row, not duplicate nodes.
            row.accessibilityDelegate = object : View.AccessibilityDelegate() {
                override fun onInitializeAccessibilityNodeInfo(host: View, info: android.view.accessibility.AccessibilityNodeInfo) {
                    super.onInitializeAccessibilityNodeInfo(host, info)
                    info.className = "android.widget.RadioButton"
                    info.isCheckable = true
                    info.isChecked = index == request.selected
                }
            }
            if (option.enabled) row.setOnClickListener { selection = index; sheet.dismiss() }
            content.addView(row)
        }
        request.footer?.let { footer -> content.addView(MaterialTextView(sheet.context).apply {
            text = footer
            setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_BodySmall)
            setPadding(dp(8), dp(8), dp(8), 0)
        }) }
        val scroll = ScrollView(sheet.context).apply { addView(content); isFillViewport = true }
        sheet.setContentView(scroll)
        sheet.setOnDismissListener {
            if (dialog === sheet) { dialog = null; requestId = null }
            results.complete(request.id, selection)
        }
        sheet.show()
        sheet.behavior.state = BottomSheetBehavior.STATE_EXPANDED
        // Shape, motion, scrim, system Back and insets remain Material-owned.
    }

    private fun dp(value: Int) = (value * activity.resources.displayMetrics.density).toInt()

    fun cancel() {
        val old = dialog
        dialog = null
        requestId = null
        results.cancel()
        old?.dismiss()
    }

    fun detach() { resumed = false; cancel(); channel.setMethodCallHandler(null) }
}
