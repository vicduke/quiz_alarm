/// Entry point of the browser "mini emulator" (see tool/emulator/run.sh).
/// It is the normal app, with SQLite swapped for the build that runs in a
/// browser. The phone app never includes this file.
library;

import 'package:quiz_alarm/data/app_database.dart';
import 'package:quiz_alarm/main.dart' as app;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

Future<void> main() async {
  AppDatabase.factoryOverride = databaseFactoryFfiWeb;
  await app.main();
}
