@file:Suppress("UNUSED_PARAMETER")
package com.gdelataillade.alarm.services
import android.content.Context
import com.gdelataillade.alarm.models.AlarmSettings
class AlarmStorage(context: Context) { companion object { val saved = ArrayList<AlarmSettings>() }
  fun getSavedAlarms(): List<AlarmSettings> = saved }
object AlarmScheduler { val scheduled = ArrayList<Int>(); var last: AlarmSettings? = null
  fun schedule(context: Context, alarm: AlarmSettings, requireDurable: Boolean = false): Boolean { scheduled.add(alarm.id); last = alarm; return true } }
