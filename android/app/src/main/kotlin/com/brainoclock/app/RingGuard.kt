package com.brainoclock.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.gdelataillade.alarm.alarm.AlarmService
import com.gdelataillade.alarm.services.AlarmScheduler
import com.gdelataillade.alarm.services.AlarmStorage

/**
 * Brings a ringing alarm back when the phone closes the app.
 *
 * Many phones close an app the moment it is swiped out of recent apps
 * (or "cleaned" on lock), and an app can crash. Either way the ringing
 * stops and nothing restarts it. This is a second, independent wake-up:
 * for every alarm the app sets, the guard is scheduled five seconds
 * after it (the shortest Android allows), and again every five seconds
 * while the alarm is unanswered. Each time it looks at the alarm:
 *
 *  - no longer stored (answered, snoozed, cancelled): nothing to do;
 *  - still ringing: all is well, look again shortly;
 *  - due, stored, but NOT ringing: the app was closed or crashed while
 *    it rang (or before it could), so it is rung again.
 *
 * It keeps looking while the alarm is unanswered, for half an hour at
 * most. A phone that fully "force stops" an app also deletes its
 * scheduled wake-ups, this one included; nothing an app does survives
 * that, which is why the alarm screen is kept out of recent apps while
 * it rings (see MainActivity).
 */
object RingGuard {
    private const val STORE = "ring_guard"

    /** How soon after the alarm, and then how often, the guard looks. */
    const val CHECK_EVERY_MS = 5_000L

    /**
     * How long this process has been running, in milliseconds. A process
     * only seconds old was started by the guard's own wake-up, which means
     * the app had been closed. (Replaced in the off-phone checks.)
     */
    @JvmField
    var processAgeMs: () -> Long = {
        if (Build.VERSION.SDK_INT >= 24) {
            android.os.SystemClock.elapsedRealtime() - android.os.Process.getStartElapsedRealtime()
        } else {
            Long.MAX_VALUE
        }
    }

    /** Unanswered for this long: stop bringing it back. */
    private const val GIVE_UP_AFTER_MS = 30 * 60_000L

    // Request codes are per receiver class, so the alarm's own id is safe.
    private fun pending(context: Context, id: Int): PendingIntent {
        val intent = Intent(context, RingGuardReceiver::class.java).putExtra("alarm_id", id)
        return PendingIntent.getBroadcast(
            context, id, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun arm(context: Context, id: Int, at: Long) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = pending(context, id)
        try {
            val exact = Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms()
            if (exact) {
                // Like the alarm itself: never held back by battery saving.
                val show = PendingIntent.getActivity(
                    context, 0,
                    Intent(context, MainActivity::class.java),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                alarms.setAlarmClock(AlarmManager.AlarmClockInfo(at, show), intent)
            } else {
                alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
            }
        } catch (e: Exception) {
            try {
                alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
            } catch (e2: Exception) {
                // No guard for this alarm; the alarm itself is unaffected.
            }
        }
    }

    /** Starts guarding alarm [id], which is due at [ringAt]. */
    fun watch(context: Context, id: Int, ringAt: Long) {
        context.getSharedPreferences(STORE, Context.MODE_PRIVATE)
            .edit().putLong(id.toString(), ringAt).apply()
        arm(context, id, ringAt + CHECK_EVERY_MS)
    }

    fun forget(context: Context, id: Int) {
        try {
            val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarms.cancel(pending(context, id))
        } catch (e: Exception) {
        }
        context.getSharedPreferences(STORE, Context.MODE_PRIVATE)
            .edit().remove(id.toString()).apply()
    }

    /**
     * The guard's moment has come for alarm [id]. Returns what it did.
     *
     * An alarm is never rung again on one look alone: a silent, unanswered
     * alarm first gets "confirm", and only a second look a moment later
     * ([confirmed]) rings it. That way an alarm caught in the instant of
     * being answered (silenced, not yet removed) is never brought back.
     */
    fun check(context: Context, id: Int, confirmed: Boolean = false): String {
        val store = context.getSharedPreferences(STORE, Context.MODE_PRIVATE)
        if (!store.contains(id.toString())) return "unknown"
        val ringAt = store.getLong(id.toString(), 0L)
        val now = System.currentTimeMillis()
        if (now - ringAt > GIVE_UP_AFTER_MS) {
            forget(context, id)
            return "gave up"
        }
        val saved = try {
            AlarmStorage(context).getSavedAlarms().firstOrNull { it.id == id }
        } catch (e: Throwable) {
            null
        }
        if (saved == null) {
            // Answered, snoozed or cancelled: the alarm is over.
            forget(context, id)
            return "over"
        }
        val due = saved.dateTime.time
        if (due > now + 2_000L) {
            // Moved to a later time under the same number: guard that time.
            store.edit().putLong(id.toString(), due).apply()
            arm(context, id, due + CHECK_EVERY_MS)
            return "not due"
        }
        val ringing = try {
            AlarmService.ringingAlarmIds.contains(id) || AlarmService.queuedAlarmIds.contains(id)
        } catch (e: Throwable) {
            false
        }
        // The app had been closed (this process is seconds old): nobody can
        // be answering it right now, so there is nothing to look at twice.
        val wasClosed = try { processAgeMs() < 4_000L } catch (e: Throwable) { false }
        if (!ringing && !confirmed && !wasClosed) {
            arm(context, id, now + CHECK_EVERY_MS)
            return "confirm"
        }
        if (!ringing) {
            // Due and unanswered, yet silent: ring it again, at full volume
            // at once (a fade-in starting over would sound like it stopped).
            try {
                val loud = try {
                    saved.copy(
                        volumeSettings = saved.volumeSettings.copy(
                            fadeDuration = null, fadeSteps = emptyList()
                        )
                    )
                } catch (e: Throwable) {
                    saved
                }
                AlarmScheduler.schedule(context, loud)
                showQuiz(context)
                store.edit().putInt("revived", store.getInt("revived", 0) + 1)
                    .putLong("revived_at", now).apply()
            } catch (e: Throwable) {
                // Try again at the next look.
            }
        }
        arm(context, id, now + CHECK_EVERY_MS)
        return if (ringing) "ringing" else "revived"
    }

    /**
     * Brings the app's screen back so the questions show again. Android
     * only lets an app do this from the background when it may "display
     * over other apps"; without that the alarm's own notification (and,
     * on a locked phone, its full-screen alarm) is the way back in.
     */
    private fun showQuiz(context: Context) {
        try {
            context.startActivity(
                Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (e: Throwable) {
        }
    }

    /** After a restart or an update: put every guard back. */
    fun restoreAll(context: Context) {
        val store = context.getSharedPreferences(STORE, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        for ((key, value) in store.all) {
            val id = key.toIntOrNull() ?: continue
            val ringAt = (value as? Long) ?: continue
            if (now - ringAt > GIVE_UP_AFTER_MS) {
                store.edit().remove(key).apply()
            } else {
                arm(context, id, maxOf(ringAt + CHECK_EVERY_MS, now + 3_000L))
            }
        }
    }

    /** How many times an alarm was brought back, and when last (for reports). */
    fun revivals(context: Context): Map<String, Any> {
        val store = context.getSharedPreferences(STORE, Context.MODE_PRIVATE)
        return mapOf(
            "count" to store.getInt("revived", 0),
            "last_at" to store.getLong("revived_at", 0L)
        )
    }

    /**
     * After an UPDATE of the app Android forgets every wake-up the app had
     * scheduled, the alarms included, and the alarm plugin only puts them
     * back after a restart of the phone. This puts back the ones still to
     * come, so an alarm set before an update rings without the app having
     * to be opened first.
     */
    fun rearmAlarms(context: Context) {
        val now = System.currentTimeMillis()
        val saved = try {
            AlarmStorage(context).getSavedAlarms()
        } catch (e: Throwable) {
            return
        }
        for (alarm in saved) {
            try {
                if (alarm.dateTime.time > now + 5_000L) AlarmScheduler.schedule(context, alarm)
            } catch (e: Throwable) {
                // One alarm that cannot be put back must not stop the rest.
            }
        }
    }
}

/** Receives the guard's wake-up (see RingGuard). */
class RingGuardReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("alarm_id", 0)
        if (id == 0) return
        // Ringing again is handed to the main thread a moment later, so the
        // process must stay alive until then.
        val result = goAsync()
        val app = context.applicationContext
        val main = Handler(Looper.getMainLooper())
        val outcome = try {
            RingGuard.check(app, id)
        } catch (e: Throwable) {
            ""
        }
        if (outcome == "confirm") {
            // Silent and unanswered: look once more before ringing it.
            main.postDelayed({
                try {
                    RingGuard.check(app, id, confirmed = true)
                } catch (e: Throwable) {
                }
            }, 1_200L)
        }
        main.postDelayed({
            try {
                result.finish()
            } catch (e: Throwable) {
            }
        }, 6_000L)
    }
}
