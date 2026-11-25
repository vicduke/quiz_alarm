import android.content.Context
import android.app.AlarmManager
import com.brainoclock.app.RingGuard
import com.gdelataillade.alarm.alarm.AlarmService
import com.gdelataillade.alarm.models.AlarmSettings
import com.gdelataillade.alarm.services.AlarmScheduler
import com.gdelataillade.alarm.services.AlarmStorage
import java.util.Date

fun expect(what: String, ok: Boolean) { println((if (ok) "ok   " else "FAIL ") + what); if (!ok) System.exit(1) }
fun main() {
    val c = Context(); val now = System.currentTimeMillis()
    // The app is running (its process is old), unless a case says otherwise.
    RingGuard.processAgeMs = { 600_000L }
    expect("an alarm nobody guards is left alone", RingGuard.check(c, 7) == "unknown")

    // Set for 5 seconds ago: the guard is armed 20 s after the alarm.
    RingGuard.watch(c, 7, now - 5_000)
    expect("watching arms the guard after the alarm", AlarmManager.armed[7] == now - 5_000 + RingGuard.CHECK_EVERY_MS)

    AlarmStorage.saved.add(AlarmSettings(7, Date(now - 5_000)))
    AlarmService.ringing = listOf(7)
    expect("ringing: nothing rung twice, looks again", RingGuard.check(c, 7) == "ringing" && AlarmScheduler.scheduled.isEmpty() && AlarmManager.armed[7]!! > now)

    AlarmService.ringing = listOf()   // the phone closed the app
    expect("silent on the first look: not rung yet, asks for a second look", RingGuard.check(c, 7) == "confirm" && AlarmScheduler.scheduled.isEmpty())
    expect("closed while ringing: rung again on the second look", RingGuard.check(c, 7, confirmed = true) == "revived" && AlarmScheduler.scheduled == listOf(7))
    expect("and it keeps looking", AlarmManager.armed[7]!! > now)
    expect("it comes back at full volume at once, with no fade-in", AlarmScheduler.last!!.volumeSettings.fadeDuration == null && AlarmScheduler.last!!.volumeSettings.fadeSteps.isEmpty() && AlarmScheduler.last!!.volumeSettings.volume == 1.0)
    expect("and the quiz is brought back to the screen", c.started == 1)
    expect("the revival is counted", (RingGuard.revivals(c)["count"] as Int) == 1)

    AlarmService.ringing = listOf(7)
    expect("back and ringing: left alone", RingGuard.check(c, 7) == "ringing" && AlarmScheduler.scheduled.size == 1)

    // Answered in the instant between the two looks: never rung again.
    AlarmService.ringing = listOf()
    expect("silenced, first look", RingGuard.check(c, 7) == "confirm")
    AlarmStorage.saved.clear()        // answered
    expect("answered before the second look: NOT rung again", RingGuard.check(c, 7, confirmed = true) == "over" && AlarmScheduler.scheduled.size == 1)
    RingGuard.watch(c, 7, now - 5_000); AlarmStorage.saved.clear()
    expect("answered: the guard ends", RingGuard.check(c, 7) == "over" && !AlarmManager.armed.containsKey(7))
    expect("and is forgotten", RingGuard.check(c, 7) == "unknown")

    // The phone closed the app: the guard's own wake-up started a new process.
    AlarmStorage.saved.clear(); AlarmScheduler.scheduled.clear()
    RingGuard.watch(c, 12, now - 5_000); AlarmStorage.saved.add(AlarmSettings(12, Date(now - 5_000)))
    AlarmService.ringing = listOf(); RingGuard.processAgeMs = { 900L }
    expect("app was closed: rung again on the FIRST look, no waiting", RingGuard.check(c, 12) == "revived" && AlarmScheduler.scheduled == listOf(12))
    RingGuard.processAgeMs = { 600_000L }
    AlarmStorage.saved.clear(); AlarmScheduler.scheduled.clear(); AlarmScheduler.scheduled.add(7)   // as it was before this case

    // Edited to a later time under the same number.
    RingGuard.watch(c, 8, now - 1_000)
    AlarmStorage.saved.add(AlarmSettings(8, Date(now + 600_000)))
    expect("moved later: not rung, guard follows the new time", RingGuard.check(c, 8) == "not due" && AlarmScheduler.scheduled.size == 1 && AlarmManager.armed[8] == now + 600_000 + RingGuard.CHECK_EVERY_MS || AlarmManager.armed[8]!! >= now + 600_000)

    // Unanswered for over half an hour.
    AlarmStorage.saved.clear(); AlarmStorage.saved.add(AlarmSettings(9, Date(now - 31 * 60_000)))
    RingGuard.watch(c, 9, now - 31 * 60_000)
    expect("after half an hour it stops bringing it back", RingGuard.check(c, 9) == "gave up" && !AlarmManager.armed.containsKey(9) && AlarmScheduler.scheduled.size == 1)

    // After an update: alarms still to come are put back, past ones are not.
    AlarmStorage.saved.clear(); AlarmScheduler.scheduled.clear()
    AlarmStorage.saved.add(AlarmSettings(20, Date(now + 3_600_000))); AlarmStorage.saved.add(AlarmSettings(21, Date(now - 3_600_000)))
    RingGuard.rearmAlarms(c)
    expect("after an update only coming alarms are re-armed", AlarmScheduler.scheduled == listOf(20))

    // After a restart: guards come back, stale ones are dropped.
    AlarmManager.armed.clear(); Context.prefs.m.clear()
    RingGuard.watch(c, 30, now + 100_000); RingGuard.watch(c, 31, now - 40 * 60_000); AlarmManager.armed.clear()
    RingGuard.restoreAll(c)
    expect("after a restart live guards return, old ones go", AlarmManager.armed.keys == setOf(30) && !Context.prefs.contains("31"))
    println("all guard checks passed")
}
