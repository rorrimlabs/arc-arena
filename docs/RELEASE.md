# Release & data-safety runbook — arena_ops MVP

One counter device, offline-first. Drift/SQLite on the device is the source of
truth; there is no server, no sync and no network in the write path.

Verified on 2026-10-11: `flutter analyze` clean, `flutter test` **274 passed**.

---

## 1. Backups

### Where they are

| Where | What |
|---|---|
| On the device | `<app Documents>/arena_ops-backups/arena_ops-v<schema>-<timestamp>Z.sqlite` |
| On this Mac (manual, pre-release) | `~/Documents/arena_ops-backups/` + `MANIFEST.txt` with sha256s |

### How they are taken

`main()` calls `DbSafety.protect` **before** the database is opened, because
Drift migrates the file the instant `AppDatabase` opens it. Each launch:

1. copies `arena_ops.sqlite` **and its `-wal`/`-shm`** aside (the write-ahead log
   holds committed rows the main file has not absorbed yet — a copy without it
   can be missing the last sessions and payments);
2. checkpoints the WAL into the copy, so a backup is one self-contained file;
3. runs `PRAGMA integrity_check` and reads back the row counts of `sessions`,
   `session_segments`, `payments`, `group_sessions`, `group_payments`,
   `bookings`, `customers`, `users`;
4. keeps the copy only if it verified, de-duplicating against an identical
   existing backup;
5. prunes to the newest 10, **never** pruning the newest backup of each distinct
   schema version.

If a migration is pending and no verified backup could be taken, the app
**refuses to open the database** and shows "Data kept safe — app not started"
instead of migrating the only copy. Nothing is changed in that state.

### Restoring

`DbSafety.restore` verifies the backup first, copies the database it is about to
replace aside (`arena_ops-replaced-<timestamp>Z.sqlite`), removes the stale
`-wal`/`-shm` (applying them over a restored file would corrupt it), then puts
the backup in place and re-verifies. A damaged backup is refused rather than
restored over good data.

To restore by hand on a Mac:

```bash
cp ~/Documents/arena_ops-backups/<chosen>.sqlite "<app Documents>/arena_ops.sqlite" && rm -f "<app Documents>/arena_ops.sqlite-wal" "<app Documents>/arena_ops.sqlite-shm"
```

---

## 2. Migrations

`schemaVersion` is **11**. `onUpgrade` walks one step per version boundary
(`_steps[n]` takes v`n` → v`n+1`) and steps must be additive — add a table, a
column or an index, never drop or rewrite user rows.

Before this work, `onUpgrade` **dropped every table** on any version change. It
no longer does. A database older than the oldest declared step has no forward
path and is rebuilt, but only behind the verified backup above, and the rebuild
is recorded in `AppDatabase.rebuiltFromVersion` rather than passing silently.

### Adding a schema change

1. bump `AppDatabase.expectedSchemaVersion`;
2. add the step to `_steps`;
3. add a case to `test/data/local/migration_test.dart` that builds a database in
   the **old** shape, writes a real session + segment + payment into it, opens it
   with the current build and asserts those rows are still correct.

`test/data/local/db_safety_test.dart` guards the framework itself: a gap in the
step chain fails the build, because a gap silently falls through to the rebuild.

---

## 3. Release builds

```bash
flutter test && flutter analyze
```

### Android

```bash
flutter build apk --release --split-per-abi
```

Artifacts in `build/app/outputs/flutter-apk/`:

| File | Size | For |
|---|---|---|
| `app-arm64-v8a-release.apk` | 24.4 MB | any modern Android tablet — **use this one** |
| `app-armeabi-v7a-release.apk` | 22.0 MB | older 32-bit devices |
| `app-release.apk` | 69.7 MB | fat APK, all ABIs |

Install on the counter tablet:

```bash
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

**Android NDK.** The build needs NDK `28.2.13676358` because `path_provider_android`
pulls in `jni`, which compiles native code. `sdkmanager` currently crashes trying
to fetch it (`NoSuchFileException`), so it was installed by hand to
`~/Library/Android/sdk/ndk/28.2.13676358` from
`https://dl.google.com/android/repository/android-ndk-r28c-darwin.zip`.

### iOS

```bash
flutter build ios --release
```

`build/ios/iphoneos/Runner.app` — 24.0 MB. Bundle id `in.rorrim.arenaOps`.
Builds clean today with `--no-codesign`; signing needs the Apple developer
account (below).

---

## 4. Signing — the remaining release blocker

Neither platform is signed for distribution yet, pending the developer account.

**Android** currently signs the release build with the **debug** key
(`android/app/build.gradle.kts` → `buildTypes.release.signingConfig =
signingConfigs.getByName("debug")`, confirmed on the built APK as
`CN=Android Debug`). The APK installs and runs for testing, but it is not a real
release and **cannot be updated later with a different key** — an app signed
with the debug key can only ever be replaced by uninstalling it, which deletes
the database. Before the counter goes live:

1. create the keystore (choose and keep the password; it cannot be recovered, and
   losing it means never being able to update the installed app):

   ```bash
   keytool -genkey -v -keystore ~/arena_ops-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

2. create `android/key.properties` (git-ignored — never commit it):

   ```
   storeFile=/Users/<you>/arena_ops-upload.jks
   storePassword=<yours>
   keyPassword=<yours>
   keyAlias=upload
   ```

3. point `buildTypes.release` at it instead of the debug config, and rebuild.

**iOS** needs the Apple developer account set as the signing team in Xcode
(`ios/Runner.xcworkspace` → Runner → Signing & Capabilities), then
`flutter build ipa`.

---

## 5. What is deliberately not in this release

- **No multi-device sync.** There is no server: no Supabase client, no HTTP
  client, nothing network-shaped in `lib/`. `AppConfig` still carries a
  `Backend.supabase` flag; with it set the UI says "Cloud not wired · Still saved
  on this device only" rather than implying a sync that does not exist.
- The design-only modules with no data model behind them (shift open/close and
  cash drawer, checklists, issue/downtime log, void approval queue, member coins
  and plans) are still absent rather than faked with placeholder numbers.
