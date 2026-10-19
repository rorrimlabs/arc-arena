#!/bin/sh
# "Check Environment" build phase of the Runner target: refuses a profile or
# release build whose flavor (the Xcode configuration, e.g. Release-prod) and
# dart-defines disagree. The iOS twin of the Gradle check in
# android/app/build.gradle.kts; the app checks every build again at start
# (lib/core/config/app_config.dart). Debug builds pass straight through.
#
# DART_DEFINES comes from Flutter/Generated.xcconfig, written by the last
# flutter command: comma-separated base64 "KEY=value" entries.
set -eu

mode=${CONFIGURATION%%-*}
case "$mode" in
  Release | Profile) ;;
  *) exit 0 ;;
esac

fail() {
  echo "error: $1"
  exit 1
}

# The value of dart-define $1, or empty when it is absent.
define() {
  old_ifs=$IFS
  IFS=,
  for entry in ${DART_DEFINES:-}; do
    kv=$(printf '%s' "$entry" | base64 --decode 2>/dev/null || true)
    case "$kv" in
      "$1="*)
        IFS=$old_ifs
        printf '%s' "${kv#*=}"
        return 0
        ;;
    esac
  done
  IFS=$old_ifs
}

case "$CONFIGURATION" in
  *-dev) flavor=dev expected=development file=dart_define.local.json ;;
  *-staging) flavor=staging expected=staging file=dart_define.staging.json ;;
  *-prod) flavor=prod expected=production file=dart_define.prod.json ;;
  *) fail "$CONFIGURATION has no flavor. Build with flutter build ios --flavor staging or --flavor prod (Xcode: the staging or prod scheme)." ;;
esac

if [ "$flavor" = dev ] && [ "$mode" = Release ]; then
  fail "The dev flavor never builds a release: local mode (demo data, default PINs) and the local stack are for development only. Build releases with --flavor staging or --flavor prod and their define file."
fi

built_flavor=$(define FLUTTER_APP_FLAVOR)
if [ "$built_flavor" != "$flavor" ]; then
  fail "Flutter/Generated.xcconfig is from a --flavor '${built_flavor:-none}' build, not $flavor. Run flutter build ios --flavor $flavor --dart-define-from-file=$file first."
fi

environment=$(define AO_ENVIRONMENT)
environment=${environment:-development}
if [ "$environment" != "$expected" ]; then
  fail "The $flavor flavor must be built for AO_ENVIRONMENT=$expected (the dart-defines say \"$environment\"): build with --dart-define-from-file=$file."
fi

if [ "$flavor" != dev ] && [ "$(define AO_BACKEND)" != supabase ]; then
  fail "The $flavor flavor is cloud-only: build with --dart-define-from-file=$file (AO_BACKEND=supabase, the project's https URL and its publishable key)."
fi
