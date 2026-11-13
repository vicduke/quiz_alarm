# BrainWake (quiz_alarm)

An alarm clock you can only switch off by answering revision questions:
**a streak of correct answers** dismisses it (easy 2, medium 3, hard 5, custom
up to 15); 5 wrong in a row unlocks a snooze of 3, 5 or 10 minutes (the
"mercy snooze"). Outside alarms, the same question bank is used for study.

## What's in the app

| Tab | What it does |
|---|---|
| **Alarms** | Alarms with repeat days, ringtone, fade-in and the topics to ask about. |
| **Question Banks** | Units -> topics with progress. Practise a topic offline: after each answer you get the correct answer and a stored explanation. "Generate with AI" adds more questions. |
| **Free Revision** | Flash cards over random or chosen topics. With a Gemini key, the AI tutor explains where your answer went wrong; offline it falls back to the stored explanation. |

| **Reports** | Totals, a 14-day chart, accuracy per topic, average time and number of questions it takes to dismiss an alarm, and the history of every alarm and practice session. Tap a session to see each question, what you answered, the correct answer and the explanation. |

Settings holds the theme, the Gemini API key / model, and the status of AI
question generation (with the real error if it fails).

## How it is built

```
lib/
  main.dart                 providers + theme
  models/models.dart        StudyUnit, Topic, Question, AlarmItem
  data/app_database.dart    SQLite schema (units, topics, questions, attempts, sessions, meta)
  data/question_repository.dart   all queries, seed import, question selection
  services/alarm_backend.dart     native alarms (alarm plugin) or simulated ones
  services/alarm_provider.dart    alarm list, scheduling, ring handling
  services/gemini_client.dart     Gemini REST calls, API key storage
  services/question_service.dart  marking, AI tutor, AI question generation
  services/bank_provider.dart     units/topics/progress for the screens
  screens/ ...                    tabs, practice (flash cards), topic, ring, edit, settings
assets/question_banks/*.json      the bundled question banks
tool/emulator/                    browser "mini emulator"
```

### Question banks

Every question lives in the local SQLite database with its **answer,
accepted alternative answers and explanation**, so the bank works offline.
Each answer you give is saved in `attempts`; that is what drives "not seen
yet", progress bars and "ask the ones I got wrong first".

Banks ship as JSON in `assets/question_banks/`, one file per unit:

```json
{
  "version": 1,
  "unit": { "id": "pharmacology", "name": "Pharmacology" },
  "topics": [
    {
      "id": "pharm-antimicrobials",
      "name": "Antimicrobials",
      "questions": [
        {
          "id": "pharm-abx-001",
          "type": "mcq",
          "text": "How do penicillins kill bacteria?",
          "options": ["They inhibit cell wall synthesis", "...", "...", "...", "..."],
          "answer": "They inhibit cell wall synthesis",
          "explanation": "Penicillins are beta-lactams ..."
        },
        {
          "id": "pharm-abx-003",
          "type": "saq",
          "text": "Which antituberculous drug turns urine orange-red?",
          "answer": "Rifampicin",
          "alt_answers": ["Rifampin"],
          "explanation": "..."
        }
      ]
    }
  ]
}
```

To change or add content: edit the file (or add a new `<unit>.json`) and
**raise `version`**. On next launch the app re-imports it. Keep question
`id`s stable: progress is tied to them. AI-generated questions and topics
the user added are never removed by a re-import.

`pharmacology.json` currently holds **starter test data** (6 placeholder
subtopics, 60 questions). Multiple-choice questions have exactly 5 options.

## Running

```bash
flutter pub get
```

```bash
flutter test
```

```bash
flutter run
```

### Mini emulator (no phone needed)

Runs the real app in a browser at phone size, with alarms simulated inside
the app and the real SQLite database.

```bash
tool/emulator/run.sh
```

Then open `http://localhost:8090/emulator.html`. Add an alarm and tap its
bell icon to make it ring in 3 seconds. It does not simulate the lock
screen, notifications, vibration or battery restrictions; those need a
real phone.

`tool/emulator/drive.js` drives it from the command line (taps, typing,
screenshots); see the comment at the top of that file.

## Notes

- Android is the tested target. iOS has the background modes the alarm
  plugin needs but has not been run on a device.
- The Android application id is still `com.example.quiz_alarm` and release
  builds are signed with the debug key. Change both before publishing
  (changing the id makes it a new app on the phone, so existing data is not
  carried over).
