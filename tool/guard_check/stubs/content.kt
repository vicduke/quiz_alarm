@file:Suppress("UNUSED_PARAMETER")
package android.content
interface SharedPreferences { val all: Map<String, *>; fun contains(k: String): Boolean; fun getLong(k: String, d: Long): Long; fun getInt(k: String, d: Int): Int; fun edit(): Editor
  interface Editor { fun putLong(k: String, v: Long): Editor; fun putInt(k: String, v: Int): Editor; fun remove(k: String): Editor; fun apply() } }
class MemPrefs : SharedPreferences, SharedPreferences.Editor { val m = HashMap<String, Any>()
  override val all: Map<String, *> get() = HashMap(m)
  override fun contains(k: String) = m.containsKey(k)
  override fun getLong(k: String, d: Long) = (m[k] as? Long) ?: d
  override fun getInt(k: String, d: Int) = (m[k] as? Int) ?: d
  override fun edit() = this
  override fun putLong(k: String, v: Long) = apply { m[k] = v }
  override fun putInt(k: String, v: Int) = apply { m[k] = v }
  override fun remove(k: String) = apply { m.remove(k) }
  override fun apply() {} }
open class Context { companion object { const val ALARM_SERVICE = "alarm"; const val MODE_PRIVATE = 0; val prefs = MemPrefs(); val alarms = android.app.AlarmManager() }
  open fun getSystemService(name: String): Any = alarms
  open fun getSharedPreferences(name: String, mode: Int): SharedPreferences = prefs
  open val applicationContext: Context get() = this
  open fun startActivity(i: Intent) { started++ }
  var started = 0 }
class Intent() { constructor(c: Context, cls: Class<*>) : this()
  companion object { const val ACTION_BOOT_COMPLETED = "b"; const val ACTION_MY_PACKAGE_REPLACED = "r"; const val FLAG_ACTIVITY_NEW_TASK = 1 }
  var action: String? = null
  fun addFlags(f: Int): Intent = this
  fun putExtra(k: String, v: Int): Intent = this
  fun getIntExtra(k: String, d: Int): Int = d }
abstract class BroadcastReceiver { class PendingResult { fun finish() {} }
  abstract fun onReceive(context: Context, intent: Intent)
  fun goAsync(): PendingResult = PendingResult() }
