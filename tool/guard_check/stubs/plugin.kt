@file:Suppress("UNUSED_PARAMETER")
package com.gdelataillade.alarm.models
import kotlin.time.Duration
data class VolumeFadeStep(val time: Duration, val volume: Double)
data class VolumeSettings(val volume: Double?, val fadeDuration: Duration?, val fadeSteps: List<VolumeFadeStep>, val volumeEnforced: Boolean, val showSystemUI: Boolean = true)
data class AlarmSettings(val id: Int, val dateTime: java.util.Date,
    val volumeSettings: VolumeSettings = VolumeSettings(1.0, Duration.parse("30s"), listOf(VolumeFadeStep(Duration.ZERO, 0.35)), true))
