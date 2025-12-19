# Pre-Fajr Notification Issue Investigation

## Problem Statement
1. **Issue #1**: Pre-Fajr notifications cannot be triggered when `notificationBeforeShuruq` is set to any non-zero value
2. **Issue #2**: Sentry error - "Maximum limit of concurrent alarms 500 reached" (Android only)

**Platforms affected:**
- Issue #1: Both iOS and Android
- Issue #2: Android only (AlarmManager limitation)

---

## Business Context (Confirmed)

| Question | Answer |
|----------|--------|
| Multiple mosques? | User can add many, but only ONE mosque can have notifications scheduled |
| `alarmIds` scope | Global (correct, since only one mosque) |
| When is `schedule()` called? | 1) App start, 2) After each notification fires, 3) Settings change |
| `notificationBeforeShuruq` behavior | Treated as main notification with Adhan/Default sound, time = Shuruq - minutes |

---

## Issue #1: Root Cause - ALARM ID COLLISION

### The Bug
The pre-Fajr alarm ID collides with the Shuruq main alarm ID, causing the Shuruq alarm to overwrite the pre-Fajr alarm.

### How Alarm IDs Are Generated

**In `prayer_services.dart` (lines 56-60):**
```dart
String indexStr = index.toString(),       // "0" for Fajr, "1" for Shuruq
    dayStr = time!.day.toString(),         // e.g., "25"
    monthStr = time.month.toString();      // e.g., "1" for January
String str = indexStr + dayStr + monthStr; // Concatenate strings
int alarmId = int.parse(str);              // Parse to int (leading zeros stripped!)
```

**In `mobile_app_notifications.dart` (line 207):**
```dart
var id = "1${prayer.alarmId}";  // Pre-notification ID = "1" + alarmId
```

### The Collision Example (January 25th)

| Prayer | Index | Raw String | Parsed alarmId |
|--------|-------|------------|----------------|
| Fajr | 0 | "0" + "25" + "1" = "0251" | **251** (leading 0 stripped) |
| Shuruq | 1 | "1" + "25" + "1" = "1251" | **1251** |

| Notification Type | ID Calculation | Final ID |
|-------------------|----------------|----------|
| Pre-Fajr | "1" + "251" | **1251** |
| Shuruq main | 1251 | **1251** |

**Pre-Fajr ID = Shuruq ID = 1251 (COLLISION!)**

### Scheduling Flow (What Actually Happens)

```
Loop iteration 1 (Fajr, index=0, alarmId=251):
  ├─ Pre-Fajr scheduled → AlarmManager.set(ID: 1251, time: 05:20)
  └─ Fajr main scheduled → AlarmManager.set(ID: 251, time: 05:30)

Loop iteration 2 (Shuruq, index=1, alarmId=1251):
  ├─ Pre-Shuruq scheduled → AlarmManager.set(ID: 11251, time: 05:50) [if enabled]
  └─ Shuruq main scheduled → AlarmManager.set(ID: 1251, time: 05:57) ← OVERWRITES Pre-Fajr!
```

**Result:** Pre-Fajr alarm (05:20) is replaced by Shuruq alarm (05:57). User never receives pre-Fajr notification.

---

## Issue #2: 500 Alarm Limit (Android)

### Analysis: Are Alarms Persisted Across App Reinstalls?

**Answer: NO.** Based on Android system behavior:

1. **On app uninstall:** All alarms registered by the app are automatically canceled by the Android system (tied to app UID)
2. **On app reinstall:** Fresh state - no alarms exist, `SharedPreferences` is cleared
3. **On app data clear:** Both alarms and SharedPreferences are cleared
4. **On device reboot:** Alarms with `rescheduleOnReboot: true` are restored, but only if the app is still installed

**Conclusion:** The 500 alarm issue is NOT caused by reinstalls. It must be from accumulated orphan alarms during normal usage.

### How Orphan Alarms Accumulate

**Scenario: Repeated `schedule()` calls with imperfect cancellation**

Each notification trigger calls `schedule()` (line 117 in `ringAlarm`). Over days/weeks:

```
Day 1, Notification 1: schedule() → Cancel old, schedule new (5-10 alarms)
Day 1, Notification 2: schedule() → Cancel old, schedule new
...
Day 30, Notification 150: schedule() → Some alarms not canceled due to ID issues
```

**Why cancellation might fail:**

1. **ID Collision in `newAlarmIds` list:**
   ```dart
   // newAlarmIds might be: ["1251", "251", "11251", "1251", ...]
   //                         ↑ Pre-Fajr      ↑ Shuruq (duplicate!)
   ```
   - Pre-Fajr ID 1251 is added
   - Shuruq ID 1251 is also added
   - List has duplicate "1251"
   - But at system level, only ONE alarm exists with ID 1251 (Shuruq overwrote Pre-Fajr)
   - **Net effect:** One alarm is "lost" from tracking but doesn't cause orphans directly

2. **Save Inside Loop (Crash Vulnerability):**
   ```dart
   // Line 272 - INSIDE the loop!
   await prefs.setStringList('alarmIds', newAlarmIds);
   ```
   - If app crashes/force-closes mid-loop:
     - Some alarms scheduled but not in saved list
     - Next `schedule()` can't cancel them → orphan alarms
   - Over many crashes (ANRs, force closes, OOM), orphans accumulate

3. **Race Condition with `isScheduling` flag:**
   ```dart
   if (isScheduling) {
     print("Scheduling in progress...");
     return;  // Early return, but alarms from interrupted session remain
   }
   ```
   - Flag is in memory, not persisted
   - On app restart, flag resets to `false`
   - Previous incomplete scheduling session's alarms become orphans

4. **ID Formula Creates Ambiguous IDs:**
   ```
   Jan 2, Fajr:  "0" + "2" + "1"  = "021"  → 21
   Feb 1, Fajr:  "0" + "1" + "2"  = "012"  → 12
   Jan 12, Fajr: "0" + "12" + "1" = "0121" → 121
   Dec 1, Duhr:  "2" + "1" + "12" = "2112" → 2112
   ```
   - String concatenation without padding creates collisions across different dates
   - When scheduling for multiple days ahead, IDs might collide

### Why 500 Is Reached

**Math:**
- Android schedules 5 prayers × 2 (pre + main) = ~10 alarms per cycle
- If 1-2 alarms become orphans per cycle (due to crashes, ID issues)
- After 250-500 notification cycles → 500 orphan alarms
- User using app for months with daily notifications could reach this

---

## Root Cause Summary

| Issue | Root Cause | Mechanism |
|-------|------------|-----------|
| #1: Pre-Fajr lost | ID collision | Pre-Fajr ID "1" + "251" = 1251 = Shuruq ID |
| #2: 500 alarms | Orphan accumulation | ID collisions + crash-vulnerable save + ambiguous ID formula |

**Both issues stem from the flawed alarm ID generation system.**

---

## Proposed Solution

### Fix 1: Robust Alarm ID Generation (prayer_services.dart)

Replace string concatenation with mathematical formula:

```dart
// Current (problematic):
String indexStr = index.toString(),
    dayStr = time!.day.toString(),
    monthStr = time.month.toString();
String str = indexStr + dayStr + monthStr;
int alarmId = int.parse(str);

// Proposed (collision-free):
// Format: PDDMM where P=prayer index (0-6), DD=day (01-31), MM=month (01-12)
int alarmId = (index * 10000) + (time!.day * 100) + time!.month;

// Examples:
// Fajr Jan 25:    0 * 10000 + 25 * 100 + 1 = 2501
// Shuruq Jan 25:  1 * 10000 + 25 * 100 + 1 = 12501  (no collision with Pre-Fajr!)
// Duhr Jan 25:    2 * 10000 + 25 * 100 + 1 = 22501
```

### Fix 2: Safe Pre-Notification ID (mobile_app_notifications.dart)

```dart
// Current (collision with Shuruq):
var id = "1${prayer.alarmId}";

// Proposed (guaranteed safe):
var id = (prayer.alarmId + 100000).toString();  // Pre-notifications in 100000+ range

// Examples:
// Pre-Fajr Jan 25:  2501 + 100000 = 102501
// Pre-Shuruq Jan 25: 12501 + 100000 = 112501
```

### Fix 3: Move Save Outside Loop (mobile_app_notifications.dart)

```dart
// Current (inside loop - crash vulnerable):
for (var i = 0; i < prayersList.length; i++) {
  // ... schedule alarms ...
  await prefs.setStringList('alarmIds', newAlarmIds);  // ← Inside loop!
}

// Proposed (outside loop - atomic):
for (var i = 0; i < prayersList.length; i++) {
  // ... schedule alarms ...
}
await prefs.setStringList('alarmIds', newAlarmIds);  // ← After loop completes
```

### Fix 4: Add Year for Cross-Year Safety (Optional)

```dart
// For absolute uniqueness across years:
int alarmId = (index * 1000000) + ((time!.year % 100) * 10000) + (time!.day * 100) + time!.month;

// Example: Fajr Jan 25, 2025 → 0 * 1000000 + 25 * 10000 + 25 * 100 + 1 = 252501
```

---

## Verification Table

### New ID Formula: No Collisions

| Prayer | Index | Day | Month | Formula | ID |
|--------|-------|-----|-------|---------|-----|
| Fajr | 0 | 25 | 1 | 0×10000 + 25×100 + 1 | **2501** |
| Pre-Fajr | - | - | - | 2501 + 100000 | **102501** |
| Shuruq | 1 | 25 | 1 | 1×10000 + 25×100 + 1 | **12501** |
| Pre-Shuruq | - | - | - | 12501 + 100000 | **112501** |
| Duhr | 2 | 25 | 1 | 2×10000 + 25×100 + 1 | **22501** |

**No collisions possible!**

---

## Implementation Checklist

- [ ] Update `prayer_services.dart` - alarm ID formula
- [ ] Update `mobile_app_notifications.dart` (Android) - pre-notification ID + save location
- [ ] Update `mobile_app_notifications.dart` (iOS) - pre-notification ID
- [ ] Test: Fajr + Shuruq both enabled with pre-notifications
- [ ] Test: Multiple days scheduling
- [ ] Test: App restart mid-scheduling (simulate crash)

---

## Questions Resolved

| Question | Answer |
|----------|--------|
| Alarms persist across reinstall? | **No** - Android clears on uninstall |
| How do 500 alarms accumulate? | Orphans from crashes + ID collisions over time |
| Why does Pre-Fajr work when Shuruq=0? | Shuruq not scheduled → no overwrite |
| Is this multi-mosque related? | **No** - only one mosque can have notifications |
