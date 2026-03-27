#!/bin/bash

# Copyright 2025 by Mayovets Vasyl. All rights reserved.
# Use of this source code is governed by a MIT license.

clear

# ==============================================================================
# GLOBAL VARS
# ==============================================================================

export FASTLANE_SKIP_UPDATE_CHECK=true
export IOS_UPLOADER="fastlane"
export ANDROID_UPLOADER="fastlane"

FLUTTER_APPS_DIR="$HOME/Projects/Flutter/Apps"
CLAUDE_SOURCE_PROJECT="$FLUTTER_APPS_DIR/octopoos/app.octopoos.platform"

# ACCESS SERVICE KEYS (from .env)
if [ -f ".env" ]; then
  set -a
  source .env
  set +a
fi
APPSTORE_KEY_PATH="${APPSTORE_KEY_PATH:-}"
PLAYSTORE_API_KEY="${PLAYSTORE_API_KEY:-}"

# CMD PARSER
COMMAND="$1"
shift || true  # shift positional $1 so $@ now contains only flags

RUN_IOS=false
RUN_ANDROID=false
RUN_WEB=false

METADATA_LOCALE="en-US"

# ==============================================================================
# FUNCTIONS
# ==============================================================================

if [[ -z "$COMMAND" ]]; then
  echo " [ ✖︎ ] -- No command provided."
  echo "Usage: $0 <command> [--all|--ios|--android|--web] [--no-git]"
  exit 1
fi

show_help() {
  echo -e "\n\033[1;34mInfo: Version management and deployment CLI\033[0m\n"

  echo -e "\033[0;32mUsage:\033[0m\n"
  echo -e "  appman <command> [options]\n"

  echo -e "\033[0;32mAvailable commands:\033[0m\n"

  echo -e "  \033[1;37mrelease\033[0m       Build and upload the app to stores"
  echo -e "     Options:"
  echo -e "       --ios           Build and upload iOS app -> AppStore"
  echo -e "       --android       Build and upload Android app -> PlayStore"
  echo -e "       --web           Build and deploy Web app -> Firebase Hosting"
  echo -e "       --all           Run all (iOS + Android + Web)\n"

  echo -e "  \033[1;37mupgrade\033[0m       Upgrade dependencies listed in pubspec.yaml"
  echo -e "     Options:"
  echo -e "       --bugfixes      Default: update only patch versions (e.g., 5.0.1 → 5.0.3)"
  echo -e "       --minor         Update minor + patch versions (e.g., 5.0.1 → 5.1.2)"
  echo -e "       --major         Update to the latest version (e.g., 5.0.1 → 6.0.0)\n"

  echo -e "  \033[1;37minit\033[0m          Initialize a new project from the base template"
  echo -e "     Prompts for: package name, bundle ID, app name, company name"
  echo -e "     Replaces identifiers across all config, platform, and Dart files\n"

  echo -e "  \033[1;37mcheck\033[0m         Check system health and project configuration"
  echo -e "     Subcommands:"
  echo -e "       tools          Check required tools are installed (default)"
  echo -e "       configs        Verify config files are filled in after init\n"
  echo -e "  \033[1;37mversion\033[0m       Sync MARKETING_VERSION and CURRENT_PROJECT_VERSION for iOS"
  echo -e "  \033[1;37mvalidate\033[0m      Validate App Store / Play Store API keys and access"
  echo -e "  \033[1;37mgitall\033[0m        Commit and push current release to production branch"
  echo -e "  \033[1;37mclean\033[0m         Clean Flutter build artifacts (flutter clean && pods upgrade)"
  echo -e "  \033[1;37msync\033[0m          Sync .claude/ settings and CLAUDE.md to another project"
  echo -e "     Subcommands:"
  echo -e "       claude        Sync Claude Code config (agents, skills, commands, CLAUDE.md)\n"
  echo -e "  \033[1;37minfo\033[0m          Show this help information\n"

  echo -e "\033[0;32mEnvironment variables (.env):\033[0m\n"
  echo -e "  APPSTORE_KEY_PATH     Path to AppStore Connect API key JSON"
  echo -e "  PLAYSTORE_API_KEY     Path to PlayStore service account JSON"
  echo -e "  IOS_UPLOADER          Uploader method: 'fastlane' or 'xcrun'"
  echo -e "  ANDROID_UPLOADER      Uploader method: 'fastlane' (default)"
  echo -e "  METADATA_LOCALE       Store metadata locale (default: en-US)\n"

  echo -e "\033[1;34mExamples:\033[0m\n"
  echo -e "  appman release --all"
  echo -e "  appman release --ios"
  echo -e "  appman upgrade --minor"
  echo -e "  appman gitall"
  echo -e "  appman info\n"

}


# --------------------
# GIT VERSION PUSH
# --------------------
push_to_prod_branch(){
  echo -e "\033[0;32m [ △ ] -- Push to git production repo ... \033[0m \n"
  git add .
  git commit -m "Publish release version $MARKETING_VERSION:$CURRENT_PROJECT_VERSION"
  git push origin production
}

# --------------------
# CHECK REQUIRED TOOLS
# --------------------
check_required_tools() {
  echo -e "\n\033[0;32m [ ◎ ] -- Check system health... \033[0m"

  REQUIRED_TOOLS=(
    "fvm"
    "flutter"
    "xcrun"
    "perl"
    "firebase"
    "fastlane"
    "git"
    "jq"
  )

  echo -e "\n\033[1;34m [ ⚙︎ ] -- Checking required tools...\033[0m\n"

  for tool in "${REQUIRED_TOOLS[@]}"; do
    command_name="${tool/-cli/}"

    if ! command -v "$command_name" &> /dev/null; then
      echo -e "\033[0;31m   [ ✖︎ ] -- $command_name not found.\033[0m"

      read -r -p "   [ ⚙︎ ] -- Install $tool using Homebrew? [y/n]: " yn
      case $yn in
        [Yy]* )
          echo -e "\033[0;34m   [ ✔︎ ] -- Installing $tool...\033[0m"
          brew install "$tool" || {
            echo -e "\033[0;31m   [ ✖︎ ] -- Failed to install $tool.\033[0m"
            exit 1
          }
          ;;
        [Nn]* )
          echo -e "\033[0;33m   [ △ ] -- Skipped installing $tool. Some commands may fail.\033[0m"
          ;;
        * )
          echo -e "\033[0;33m   [ ✖︎ ] -- Invalid input. Skipping $tool.\033[0m"
          ;;
      esac
    else
      echo -e "\033[1;34m   [ ✔︎ ] \033[0m-- $command_name is installed"
    fi
  done

  echo -e "\n"
}

# --------------------
# IOS PODS REBUILD
# --------------------
clean_rebuild_deps() {
  echo -e "\n\033[0;32m [ ◎ ] -- Cleaning Flutter project... \033[0m\n"
  fvm flutter clean

  echo -e "\n\033[0;32m [ ◎ ] -- Getting Flutter packages... \033[0m\n"
  fvm flutter pub get

  echo -e "\n\033[0;32m [ ◎ ] -- Updating CocoaPods... \033[0m\n"
  cd ios || { echo " [ ✖︎ ] -- Failed to enter ios/ directory"; exit 1; }

  pod repo update

  if pod update; then
    echo -e "\n\033[0;32m [ ✔︎ ] -- Pods updated successfully.\033[0m"
  else
    echo -e "\033[0;33m [ △ ] -- Pod update failed, trying pod install...\033[0m"
    pod install || {
      echo -e "\033[0;31m [ ✖︎ ] -- Pod install failed.\033[0m"
      exit 1
    }
  fi

  cd ..
  echo -e "\n\033[0;32m [ ✔︎ ] -- iOS pods rebuild completed.\033[0m\n"
}

# --------------------
# RELEASE IOS APPS
# --------------------
ios_update_version() {
  FILE="ios/Runner.xcodeproj/project.pbxproj"

  echo -e "\n\033[0;32m [ ▽ ] -- Backup pbxproj settings... \033[0m"
  cp "$FILE" "${FILE}.backup"

  echo -e "\n\033[0;32m [ ◎ ] -- Update pbxproj version & build... \033[0m"
  perl -0777 -i -pe '
    my $v1 = $ENV{"MARKETING_VERSION"};
    my $v2 = $ENV{"CURRENT_PROJECT_VERSION"};

    # Update all MARKETING_VERSION and CURRENT_PROJECT_VERSION
    s/\bMARKETING_VERSION\s*=\s*[\d.]+;/MARKETING_VERSION = $v1;/g;
    s/\bCURRENT_PROJECT_VERSION\s*=\s*\d+;/CURRENT_PROJECT_VERSION = $v2;/g;
  ' "$FILE"
}

ios_appstore_release() {
  if [ "$RUN_IOS" = true ]; then
    ios_update_version

    echo -e "\n\033[0;32m [ ◎ ] -- Building iOS IPA... \033[0m\n\n"
    fvm flutter build ipa \
          --release \
          --obfuscate \
          --build-name "$MARKETING_VERSION" \
          --build-number "$CURRENT_PROJECT_VERSION" \
          --split-debug-info=build/symbols/ios

    IPA_PATH=$(find build/ios/ipa -name "*.ipa" | head -n 1)
    if [[ -z "$IPA_PATH" || ! -f "$IPA_PATH" ]]; then
      echo " [ ✖︎ ] -- IPA file not found"
      exit 1
    fi

    echo -e "\n\033[0;32m [ ◎ ] -- AppStore Connect validate... \033[0m \n"
    xcrun altool \
      --validate-app \
      --type ios \
      --file build/ios/ipa/*.ipa \
      --apiKey "$APPSTORE_API_KEY" \
      --apiIssuer "$APPSTORE_API_ISSUER"

    echo -e "\n\033[0;32m [ ◎ ] -- AppStore Connect upload... \033[0m \n"
    case "$IOS_UPLOADER" in
      xcrun)
        xcrun altool \
          --upload-app \
          --type ios \
          -f build/ios/ipa/*.ipa \
          --apiKey "$APPSTORE_API_KEY" \
          --apiIssuer "$APPSTORE_API_ISSUER"
      ;;
      fastlane)
        fastlane run upload_to_app_store \
          ipa:"$IPA_PATH" \
          api_key_path:"$APPSTORE_KEY_PATH" \
          submit_for_review:false \
          skip_metadata:true \
          skip_screenshots:true \
          metadata_path:"./storage/metadata/ios" \
          precheck_include_in_app_purchases:false \
          automatic_release:false
      ;;
      *)
        echo " [ ✖ ︎] -- IOS_UPLOADER must be 'fastlane or xcrun', but got '$IOS_UPLOADER'"
        exit 1
      ;;
    esac
  fi
}

# --------------------
# RELEASE ANDROID APP
# --------------------
android_playstore_release() {
  if [ "$RUN_ANDROID" = true ]; then
    echo -e "\n\033[0;32m [ ◎ ] -- Building Android AAB... \033[0m\n"
    fvm flutter build appbundle \
          --release \
          --obfuscate \
          --build-name "$MARKETING_VERSION" \
          --build-number "$CURRENT_PROJECT_VERSION" \
          --split-debug-info=build/symbols/android

    PACKAGE_NAME="$BUNDLE_ID"
    AAB_PATH="build/app/outputs/bundle/release/app-release.aab"
    TRACK="production"

    if [ ! -f "$AAB_PATH" ]; then
      echo " [ ✖︎ ] -- AAB file not found"; exit 1
    fi

    echo -e "\n\033[0;32m [ ◎ ] -- Uploading AAB to Google Play Console...\033[0m \n"
    case "$ANDROID_UPLOADER" in
      fastlane)
        fastlane run upload_to_play_store \
         json_key:"$PLAYSTORE_API_KEY" \
         package_name:"$PACKAGE_NAME" \
         track:"$TRACK" \
         aab:"$AAB_PATH" \
         skip_upload_metadata:true \
         skip_upload_images:true \
         skip_upload_screenshots:true \
         metadata_path:"./storage/metadata/android" \
         changes_not_sent_for_review:true \
         release_status:"draft"
      ;;
      *)
        echo " [ ✖︎ ] -- ANDROID_UPLOADER must be 'fastlane', but got '$ANDROID_UPLOADER'"
        exit 1
      ;;
    esac
  fi
}

# --------------------
# CRASHLYTICS SYMBOLS
# --------------------
crashlytics_symbols_upload() {
  echo -e "\n\033[0;32m [ ◎ ] -- Crashlytics symbols upload started... \033[0m\n"

  ANDROID_SYMBOLS_DIR="build/symbols/android"
  IOS_SYMBOLS_DIR="build/symbols/ios"

  ANDROID_APP_ID=$(jq -r '.client[0].client_info.mobilesdk_app_id' android/app/google-services.json)
  IOS_APP_ID=$(/usr/libexec/PlistBuddy -c "Print :GOOGLE_APP_ID" ios/Runner/GoogleService-Info.plist)

  # Android
  if [ -d "$ANDROID_SYMBOLS_DIR" ]; then
    echo -e "\033[1;34m [ ↑ ] -- Upload Android symbols from: $ANDROID_SYMBOLS_DIR \033[0m\n"
    firebase crashlytics:symbols:upload \
      --app="$ANDROID_APP_ID" \
      "$ANDROID_SYMBOLS_DIR"
    echo -e "\033[0;32m [ ✔︎ ] -- Android symbols uploaded. \033[0m\n"
  else
    echo -e "\033[0;33m [ △ ] -- Android symbols directory not found, skipping. \033[0m\n"
  fi

  # iOS
  if [ -d "$IOS_SYMBOLS_DIR" ]; then
    echo -e "\033[1;34m [ ↑ ] -- Upload iOS symbols from: $IOS_SYMBOLS_DIR \033[0m\n"
    firebase crashlytics:symbols:upload \
      --app="$IOS_APP_ID" \
      --debug-symbols="$IOS_SYMBOLS_DIR"
    echo -e "\033[0;32m [ ✔︎ ] -- iOS symbols uploaded. \033[0m\n"
  else
    echo -e "\033[0;33m [ △ ] -- iOS symbols directory not found, skipping. \033[0m\n"
  fi

  echo -e "\033[0;32m [ ✔︎ ] -- Crashlytics symbols upload complete.\033[0m\n"
}

# --------------------
# RELEASE WEBAPP
# --------------------
webapp_firebase_release(){
  if [ "$RUN_WEB" = true ]; then
    echo -e "\n\033[0;32m [ ◎ ] -- Building Web... \033[0m\n"
    fvm flutter build web

    # Read Firebase project ID from .firebaserc
    if [ -f .firebaserc ]; then
      FIREBASE_PROJECT_ID=$(jq -r '.projects.default' .firebaserc)
    else
      echo " [ ✖︎ ] -- .firebaserc not found"
      exit 1
    fi

    echo -e "\n\033[0;32m [ ◎ ] -- Use Firebase project '$FIREBASE_PROJECT_ID' ... \033[0m\n"
    firebase use "$FIREBASE_PROJECT_ID"

    echo -e "\n\033[0;32m [ ◎ ] -- Deploying Web to Firebase... \033[0m"
    firebase deploy --only hosting
  fi
}

# --------------------
# UPDATE SDK DEPS
# --------------------
check_sdk_deps(){
  echo -e "\033[0;32m [ ✔︎ ] -- Getting packages... \033[0m\n"
  fvm flutter pub get
}

# ----------------------
# VALIDATE DEPLOY ACCESS
# ----------------------
validate_environment() {
  echo -e "\n\033[0;32m [ ◎ ] -- Running environment test... \033[0m"

  # Check App Store API key
  if [ -f "$APPSTORE_KEY_PATH" ]; then
    echo -e "\n\033[1;34m [ ✔︎︎ ] -- Validating AppStore Keys... \033[0m\n"
    fastlane run app_store_build_number \
      api_key_path:"$APPSTORE_KEY_PATH" \
      app_identifier:"$BUNDLE_ID"
  else
    echo -e "\n\033[0;31m [ ✖︎ ] -- AppStore keys not found at $APPSTORE_KEY_PATH \033[0m"
  fi

  # Check Play Store API key
  if [ -f "$PLAYSTORE_API_KEY" ]; then
    echo -e "\n\033[1;34m [ ✔︎︎ ] -- Validating PlayStore Keys... \033[0m\n"
    fastlane run google_play_track_version_codes \
      json_key:"$PLAYSTORE_API_KEY" \
      package_name:"$BUNDLE_ID" \
      track:"production"
  else
    echo -e "\n\033[0;31m [ ✖︎ ] -- PlayStore keys not found at $PLAYSTORE_API_KEY \033[0m"
  fi
}

# --------------------
# GEN RELEASE METADATA
# --------------------
generate_metadata() {
  # Ensure METADATA folders exist
  echo -e "\n\033[0;32m [ ✔︎ ] -- Metadata checks... \033[0m"
  for dir in ./storage/metadata/android ./storage/metadata/ios; do
    if [ ! -d "$dir" ]; then
      mkdir -p "$dir"
    fi
  done

  echo -e "\n\033[0;32m [ ◎ ] -- Preparing What's New metadata... \033[0m"

  # Correct Play Store locale code
  BASE_DIR="./storage/metadata"

  IOS_DIR="$BASE_DIR/ios/$METADATA_LOCALE"
  ANDROID_DIR="$BASE_DIR/android/$METADATA_LOCALE/changelogs"

  CHANGELOG_FILE="./changelog.md"

  mkdir -p "$IOS_DIR" "$ANDROID_DIR"

  if [ ! -f "$CHANGELOG_FILE" ]; then
    echo "* Performance improvements and bug fixes;" > "$CHANGELOG_FILE"
    echo " [ ✔︎ ] -- Created default CHANGELOG.md"
  fi

  WHATS_NEW=$(cat "$CHANGELOG_FILE" | sed '/^\s*$/d')
  if [ -z "$WHATS_NEW" ]; then
    WHATS_NEW="* Performance improvements and bug fixes;"
  fi

  IOS_FILE="$IOS_DIR/whats_new.txt"
  echo "$WHATS_NEW" > "$IOS_FILE"

  ANDROID_FILE="$ANDROID_DIR/$CURRENT_PROJECT_VERSION.txt"
  echo "$WHATS_NEW" > "$ANDROID_FILE"

  echo -e "\n\033[0;32m [ ◎ ] -- What's New prepared for version $MARKETING_VERSION ($CURRENT_PROJECT_VERSION) [$MLOCALE]\033[0m\n"
}

# ----------------------
# CLEAN RELEASE METADATA
# ----------------------
cleanup_metadata() {
  echo -e "\n\033[0;32m [ ◎ ] -- Cleaning up metadata files... \033[0m\n"

  BASE_DIR="./storage/metadata"

  find "$BASE_DIR/android" -type f -path "*/changelogs/*.txt" -delete
  find "$BASE_DIR/ios" -type f -name "whats_new.txt" -delete

  CHANGELOG_FILE="./changelog.md"
  if [ -f "$CHANGELOG_FILE" ]; then
    > "$CHANGELOG_FILE"
    echo " [ ✔︎ ] -- CHANGELOG.md cleared"
  fi

  echo -e "\n\033[0;32m [ ◎ ] -- Metadata cleanup complete \033[0m\n"
}

# ----------------------
# PUBSPEC PKGS UPGRADER
# ----------------------
upgrade_dependencies() {
  echo -e "\n\033[0;32m [ ◎ ] -- Checking for package updates... \033[0m\n"

  UPGRADE_LEVEL="bugfixes" # default
  for arg in "$@"; do
    case $arg in
      --major)    UPGRADE_LEVEL="major" ;;
      --minor)    UPGRADE_LEVEL="minor" ;;
      --bugfixes) UPGRADE_LEVEL="bugfixes" ;;
      *)
        echo " [ ✖︎ ] -- Unknown option: $arg"
        echo "Usage: $0 upgrade [--major|--minor|--bugfixes]"
        exit 1
        ;;
    esac
  done

  # 1. Parse current pubspec.yaml
  if [ ! -f "pubspec.yaml" ]; then
    echo " [ ✖︎ ] -- pubspec.yaml not found"
    exit 1
  fi

  TMP_FILE=$(mktemp)
  cp pubspec.yaml "$TMP_FILE"

  # 2. Get all dependencies list
  echo -e "\033[1;34m [ ⚙︎ ] -- Fetching latest package versions...\033[0m\n"

  while IFS= read -r line; do
    if [[ $line =~ ^[[:space:]]*([a-zA-Z0-9_-]+):[[:space:]]*\^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
      PACKAGE="${BASH_REMATCH[1]}"
      MAJOR="${BASH_REMATCH[2]}"
      MINOR="${BASH_REMATCH[3]}"
      PATCH="${BASH_REMATCH[4]}"

      # Query pub.dev API for the latest version
      LATEST=$(curl -s "https://pub.dev/api/packages/$PACKAGE" | jq -r '.latest.version' 2>/dev/null)

      if [[ -z "$LATEST" || "$LATEST" == "null" ]]; then
        continue
      fi

      # Split latest version
      if [[ $LATEST =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        L_MAJOR="${BASH_REMATCH[1]}"
        L_MINOR="${BASH_REMATCH[2]}"
        L_PATCH="${BASH_REMATCH[3]}"
      fi

      # 3. Compare versions and decide if update allowed
      DO_UPDATE=false
      case $UPGRADE_LEVEL in
        bugfixes)
          if (( L_MAJOR == MAJOR && L_MINOR == MINOR && L_PATCH > PATCH )); then
            DO_UPDATE=true
          fi
          ;;
        minor)
          if (( L_MAJOR == MAJOR && (L_MINOR > MINOR || (L_MINOR == MINOR && L_PATCH > PATCH)) )); then
            DO_UPDATE=true
          fi
          ;;
        major)
          if (( L_MAJOR > MAJOR || L_MINOR > MINOR || L_PATCH > PATCH )); then
            DO_UPDATE=true
          fi
          ;;
      esac

      # 4. Update pubspec.yaml (inline, keeping indentation)
      if [ "$DO_UPDATE" = true ]; then
        OLD_VER="^${MAJOR}.${MINOR}.${PATCH}"
        NEW_VER="^${L_MAJOR}.${L_MINOR}.${L_PATCH}"
        echo " [ ↑ ] $PACKAGE: $OLD_VER → $NEW_VER"
        perl -pi -e "s/(^[[:space:]]*$PACKAGE:[[:space:]]*)\\^${MAJOR}\\.${MINOR}\\.${PATCH}/\${1}${NEW_VER}/" pubspec.yaml
      fi
    fi
  done < "$TMP_FILE"

  rm "$TMP_FILE"

  echo -e "\n\033[0;32m [ ✔︎ ] -- Dependencies updated according to '$UPGRADE_LEVEL' policy.\033[0m\n"
  echo -e "\033[0;32m [ ◎ ] -- Running flutter pub get ...\033[0m\n"
  fvm flutter pub get
  fvm flutter pub upgrade
}

deploy_info(){
  echo -e "\n\033[0;32m [ ✔︎ ] -- All Done! \033[0m\n"
}

# ==============================================================================
# INIT: PROJECT INITIALIZATION
# ==============================================================================

# Template defaults (what the base project currently has)
_OLD_PKG="octopus"
_OLD_BUNDLE="app.octopoos.platform"
_OLD_BUNDLE_TYPO="app.ctopoos.platform"
_OLD_APP_NAME="Octopus"
_OLD_DISPLAY_NAME="Platform"
_OLD_COMPANY="OCTOPUS"
_OLD_COMPANY_FULL="Octopus Apps"
_OLD_HIVE="octopoos"
_OLD_FIREBASE_PROJECT="app-octopoos-platform"
_OLD_GID_CLIENT_ID_IOS="746237677326-c4glfncvje43sgs36dgrodalsl3cj7tr.apps.googleusercontent.com"
_OLD_GID_CLIENT_ID_WEB="746237677326-hk6u80hhc8k2raj5ba4k3oni3natip30.apps.googleusercontent.com"
FIREBASE_CONFIGURED=false

init_check_prerequisites() {
  if [ -f ".appinit.conf" ]; then
    echo -e "\033[0;33m [ ! ] -- Project already initialized.\033[0m"
    cat .appinit.conf
    echo ""
    read -r -p "   Re-run init? [y/n]: " yn
    case $yn in
      [Yy]* ) echo -e "\033[0;33m [ ! ] -- Re-initializing...\033[0m" ;;
      * ) echo " [ . ] -- Aborted."; exit 0 ;;
    esac
  fi

  if ! command -v perl &>/dev/null; then
    echo " [ ✖︎ ] -- perl is required but not found"; exit 1
  fi

  if ! command -v fvm &>/dev/null; then
    echo " [ ✖︎ ] -- fvm is required but not found"; exit 1
  fi
}

init_collect_inputs() {
  echo -e "\n\033[1;34m [ ⚙︎ ] -- Project initialization\033[0m\n"

  # Package name (default: octopus)
  while true; do
    read -r -p "   Dart package name [octopus]: " INIT_PKG_NAME
    INIT_PKG_NAME="${INIT_PKG_NAME:-octopus}"
    if [[ "$INIT_PKG_NAME" =~ ^[a-z][a-z0-9_]*$ ]]; then
      break
    fi
    echo "   [ ✖︎ ] -- Must be lowercase letters, digits, underscores. Start with a letter."
  done

  # Bundle ID
  while true; do
    read -r -p "   Bundle ID (e.g. com.company.app): " INIT_BUNDLE_ID
    if [[ "$INIT_BUNDLE_ID" =~ ^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*){2,}$ ]]; then
      break
    fi
    echo "   [ ✖︎ ] -- Use reverse domain notation (e.g. com.company.myapp)"
  done

  # App display name
  while true; do
    read -r -p "   App display name: " INIT_APP_NAME
    if [[ -n "$INIT_APP_NAME" ]]; then break; fi
    echo "   [ ✖︎ ] -- Cannot be empty."
  done

  # Company name (short, uppercase branding)
  while true; do
    read -r -p "   Company name (short): " INIT_COMPANY
    if [[ -n "$INIT_COMPANY" ]]; then break; fi
    echo "   [ ✖︎ ] -- Cannot be empty."
  done

  # Company full name
  while true; do
    read -r -p "   Company full name: " INIT_COMPANY_FULL
    if [[ -n "$INIT_COMPANY_FULL" ]]; then break; fi
    echo "   [ ✖︎ ] -- Cannot be empty."
  done

  # Hive container slug
  while true; do
    local default_hive
    default_hive=$(echo "$INIT_PKG_NAME" | tr -d '_')
    read -r -p "   Hive storage container [$default_hive]: " INIT_HIVE
    INIT_HIVE="${INIT_HIVE:-$default_hive}"
    if [[ "$INIT_HIVE" =~ ^[a-z][a-z0-9_]*$ ]]; then
      break
    fi
    echo "   [ ✖︎ ] -- Lowercase letters, digits, underscores only."
  done
}

init_confirm() {
  echo -e "\n\033[1;34m   Summary:\033[0m"
  echo "   ─────────────────────────────────"
  echo "   Package name:    $INIT_PKG_NAME"
  echo "   Bundle ID:       $INIT_BUNDLE_ID"
  echo "   App name:        $INIT_APP_NAME"
  echo "   Company:         $INIT_COMPANY"
  echo "   Company full:    $INIT_COMPANY_FULL"
  echo "   Hive container:  $INIT_HIVE"
  echo "   ─────────────────────────────────"
  echo ""

  read -r -p "   Proceed? [y/n]: " yn
  case $yn in
    [Yy]* ) ;;
    * ) echo " [ . ] -- Aborted."; exit 0 ;;
  esac
}

init_save_config() {
  cat > .appinit.conf <<CONF
PKG_NAME=$INIT_PKG_NAME
BUNDLE_ID=$INIT_BUNDLE_ID
APP_NAME=$INIT_APP_NAME
COMPANY=$INIT_COMPANY
COMPANY_FULL=$INIT_COMPANY_FULL
HIVE_CONTAINER=$INIT_HIVE
INITIALIZED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CONF
  echo -e "\n\033[0;32m [ ✔︎ ] -- Config saved to .appinit.conf\033[0m"
}

init_replace_pubspec() {
  echo -e "\033[0;32m [ ◎ ] -- Updating pubspec.yaml...\033[0m"
  perl -pi -e "s/^name: $_OLD_PKG\$/name: $INIT_PKG_NAME/" pubspec.yaml
  perl -pi -e "s/^bundle: $_OLD_BUNDLE\$/bundle: $INIT_BUNDLE_ID/" pubspec.yaml
}

init_replace_android() {
  echo -e "\033[0;32m [ ◎ ] -- Updating Android configs...\033[0m"

  # build.gradle.kts — namespace & applicationId
  perl -pi -e "s/app\\.octopoos\\.platform/$INIT_BUNDLE_ID/g" android/app/build.gradle.kts

  # AndroidManifest.xml — package
  perl -pi -e "s/app\\.octopoos\\.platform/$INIT_BUNDLE_ID/g" android/app/src/main/AndroidManifest.xml

  # strings.xml — app name
  perl -pi -e "s/>Octopus</>$INIT_APP_NAME</" android/app/src/main/res/values/strings.xml

  # MainActivity.kt — package declaration & MethodChannel
  local KT_FILE="android/app/src/main/kotlin/app/octopoos/platform/MainActivity.kt"
  if [ -f "$KT_FILE" ]; then
    perl -pi -e "s/^package app\\.octopoos\\.platform/package $INIT_BUNDLE_ID/" "$KT_FILE"
    perl -pi -e "s/app\\.octopoos\\.platform/$INIT_BUNDLE_ID/g" "$KT_FILE"
  fi
}

init_rename_android_kotlin() {
  echo -e "\033[0;32m [ ◎ ] -- Moving Kotlin package directory...\033[0m"

  local OLD_DIR="android/app/src/main/kotlin/app/octopoos/platform"
  local NEW_DIR
  NEW_DIR="android/app/src/main/kotlin/$(echo "$INIT_BUNDLE_ID" | tr '.' '/')"

  if [ -d "$OLD_DIR" ] && [ "$OLD_DIR" != "$NEW_DIR" ]; then
    mkdir -p "$NEW_DIR"
    mv "$OLD_DIR"/*.kt "$NEW_DIR/" 2>/dev/null
    # Clean up empty old directories
    rm -rf "android/app/src/main/kotlin/app/octopoos" 2>/dev/null
    echo -e "\033[0;32m [ ✔︎ ] -- Kotlin dir: $NEW_DIR\033[0m"
  fi
}

init_replace_ios() {
  echo -e "\033[0;32m [ ◎ ] -- Updating iOS configs...\033[0m"

  # project.pbxproj — PRODUCT_BUNDLE_IDENTIFIER
  perl -pi -e "s/app\\.octopoos\\.platform/$INIT_BUNDLE_ID/g" ios/Runner.xcodeproj/project.pbxproj

  # Info.plist — bundle ID typo fix
  perl -pi -e "s/app\\.ctopoos\\.platform/$INIT_BUNDLE_ID/g" ios/Runner/Info.plist

  # Info.plist — CFBundleName (targeted: after <key>CFBundleName</key>)
  perl -0777 -pi -e "s/(<key>CFBundleName<\\/key>\\s*<string>)Octopus(<\\/string>)/\${1}$INIT_APP_NAME\${2}/g" ios/Runner/Info.plist

  # Info.plist — CFBundleDisplayName (targeted: after <key>CFBundleDisplayName</key>)
  perl -0777 -pi -e "s/(<key>CFBundleDisplayName<\\/key>\\s*<string>)Platform(<\\/string>)/\${1}$INIT_APP_NAME\${2}/g" ios/Runner/Info.plist

  # Info.plist — NSHumanReadableCopyright
  perl -pi -e "s/Octopoos Research LLC/$INIT_COMPANY_FULL/g" ios/Runner/Info.plist
}

init_replace_web() {
  echo -e "\033[0;32m [ ◎ ] -- Updating Web configs...\033[0m"

  if [ -f "web/index.html" ]; then
    perl -pi -e "s/Octopus Streaks/$INIT_APP_NAME/g" web/index.html
    perl -pi -e "s/Octopus: Streaks & Habits/$INIT_APP_NAME/g" web/index.html
  fi

  if [ -f "web/manifest.json" ]; then
    perl -pi -e "s/Octopus Streaks/$INIT_APP_NAME/g" web/manifest.json
  fi
}

init_replace_dart_configs() {
  echo -e "\033[0;32m [ ◎ ] -- Updating Dart configs...\033[0m"

  # app.dart
  local F="lib/app/configs/app.dart"
  perl -pi -e "s/companyName = \"OCTOPUS\"/companyName = \"$INIT_COMPANY\"/" "$F"
  perl -pi -e "s/productName = 'Apps That Empower'/productName = '$INIT_APP_NAME'/" "$F"
  perl -pi -e "s/bundleName = 'octopus\\.platform'/bundleName = '$INIT_PKG_NAME'/" "$F"
  perl -pi -e "s/appName = 'Platform'/appName = '$INIT_APP_NAME'/" "$F"
  perl -pi -e "s/byDevs = 'by Octopus Apps'/byDevs = 'by $INIT_COMPANY_FULL'/" "$F"
  perl -pi -e "s/bundleIdentifier = 'app\\.octopoos\\.platform'/bundleIdentifier = '$INIT_BUNDLE_ID'/" "$F"

  # storage.dart
  perl -pi -e "s/container = 'octopoos'/container = '$INIT_HIVE'/" lib/app/configs/storage.dart

  # cache.dart
  perl -pi -e "s/directoryName = 'app\\.octopoos\\.platform'/directoryName = '$INIT_BUNDLE_ID'/" lib/app/configs/cache.dart

  # prod.dart
  perl -pi -e "s/playStoreID = \"app\\.octopoos\\.platform\"/playStoreID = \"$INIT_BUNDLE_ID\"/" lib/app/configs/prod.dart

  # MethodChannel references
  find lib -name '*.dart' -exec perl -pi -e "s/app\\.octopoos\\.platform/$INIT_BUNDLE_ID/g" {} +
}

init_rename_dart_imports() {
  if [ "$INIT_PKG_NAME" = "$_OLD_PKG" ]; then
    echo -e "\033[0;33m [ △ ] -- Package name unchanged (octopus), skipping import rename.\033[0m"
    return
  fi

  echo -e "\033[0;32m [ ◎ ] -- Renaming Dart imports (package:$_OLD_PKG → package:$INIT_PKG_NAME)...\033[0m"
  find lib test -name '*.dart' -exec perl -pi -e "s/package:$_OLD_PKG\\//package:${INIT_PKG_NAME}\\//g" {} +
  echo -e "\033[0;32m [ ✔︎ ] -- Dart imports renamed.\033[0m"
}

init_replace_i18n() {
  echo -e "\033[0;32m [ ◎ ] -- Updating i18n brand strings...\033[0m"

  # Replace 'Octopus' in string values (after quotes), not in getter names
  find lib/app/i18n -name '*.dart' -exec perl -pi -e "s/'Octopus/'$INIT_APP_NAME/g" {} +
  find lib/app/i18n -name '*.dart' -exec perl -pi -e 's/\"Octopus/\"'"$INIT_APP_NAME"'/g' {} +
}

init_replace_docs() {
  echo -e "\033[0;32m [ ◎ ] -- Updating CLAUDE.md & appman.sh...\033[0m"

  # CLAUDE.md — update only the header block (lines 1-9), preserve rest
  if [ -f "CLAUDE.md" ]; then
    # Replace the description line (bold line with app name)
    perl -pi -e 's/^\*\*.*\*\* — a Flutter app.*$/\*\*'"$INIT_APP_NAME"'\*\* — a Flutter app (iOS, Android, Web) by '"$INIT_COMPANY"' Apps./' CLAUDE.md
    # Update Package name line
    perl -pi -e "s/^- Package name: \`.+\`.*/- Package name: \`$INIT_PKG_NAME\` (import as \`package:${INIT_PKG_NAME}\/...\`)/" CLAUDE.md
    # Update Bundle ID line
    perl -pi -e "s/^- Bundle ID: \`.+\`.*/- Bundle ID: \`$INIT_BUNDLE_ID\`/" CLAUDE.md
    # Update Dart SDK from pubspec.yaml
    local DART_SDK
    DART_SDK=$(perl -ne 'print $1 if /^\s+sdk:\s+"(.+)"/' pubspec.yaml)
    if [ -n "$DART_SDK" ]; then
      perl -pi -e "s/^- Dart SDK: \`.+\`/- Dart SDK: \`$DART_SDK\`/" CLAUDE.md
    fi
    # Update package imports in code examples (package:old → package:new)
    if [ "$INIT_PKG_NAME" != "$_OLD_PKG" ]; then
      perl -pi -e "s/package:$_OLD_PKG\\//package:${INIT_PKG_NAME}\\//g" CLAUDE.md
    fi
  fi

  # Create .env with service key paths
  local SAFE_PKG
  SAFE_PKG=$(echo "$INIT_PKG_NAME" | tr '_' '-')
  cat > .env << ENVEOF
APPSTORE_KEY_PATH=\$HOME/.servicekeys/appstore-${SAFE_PKG}-appman.json
PLAYSTORE_API_KEY=\$HOME/.servicekeys/playstore-${SAFE_PKG}-appman.json
ENVEOF
  echo -e "  \033[0;32m✓\033[0m .env (service keys)"
}

init_firebase_setup() {
  echo -e "\n\033[1;34m [ ⚙︎ ] -- Firebase Setup\033[0m\n"
  echo -e "   A Firebase project must be created before proceeding."
  echo -e "   Create one at: \033[4mhttps://console.firebase.google.com\033[0m\n"

  read -r -p "   Have you created a Firebase project? [y/n]: " yn
  case $yn in
    [Yy]* ) ;;
    * )
      echo -e "\033[0;33m [ △ ] -- Skipping Firebase setup. Complete it manually later.\033[0m"
      return
      ;;
  esac

  # Firebase project ID
  while true; do
    read -r -p "   Firebase project ID (e.g. app-octopus-platform): " INIT_FIREBASE_PROJECT
    if [[ -n "$INIT_FIREBASE_PROJECT" && "$INIT_FIREBASE_PROJECT" =~ ^[a-z][a-z0-9-]*$ ]]; then
      break
    fi
    echo "   [ ✖︎ ] -- Must be lowercase letters, digits, and hyphens. Start with a letter."
  done

  # Update .firebaserc
  echo -e "\033[0;32m [ ◎ ] -- Updating .firebaserc...\033[0m"
  perl -pi -e "s/\Q$_OLD_FIREBASE_PROJECT\E/$INIT_FIREBASE_PROJECT/g" .firebaserc

  # Update firebase.json
  echo -e "\033[0;32m [ ◎ ] -- Updating firebase.json...\033[0m"
  perl -pi -e "s/\Q$_OLD_FIREBASE_PROJECT\E/$INIT_FIREBASE_PROJECT/g" firebase.json

  # Update app.dart — storageBucket (gs://{projectId}.appspot.com)
  echo -e "\033[0;32m [ ◎ ] -- Updating app.dart — storageBucket...\033[0m"
  perl -pi -e "s/\Q$_OLD_FIREBASE_PROJECT\E/$INIT_FIREBASE_PROJECT/g" lib/app/configs/app.dart

  # Update auth.dart — socialRedirectURL (https://{projectId}.firebaseapp.com/...)
  echo -e "\033[0;32m [ ◎ ] -- Updating auth.dart — socialRedirectURL...\033[0m"
  perl -pi -e "s/\Q$_OLD_FIREBASE_PROJECT\E/$INIT_FIREBASE_PROJECT/g" lib/app/configs/auth.dart

  # Update openai.dart — Cloud Functions endpoint (us-central1-{projectId}.cloudfunctions.net)
  echo -e "\033[0;32m [ ◎ ] -- Updating openai.dart — Cloud Functions endpoint...\033[0m"
  perl -pi -e "s/\Q$_OLD_FIREBASE_PROJECT\E/$INIT_FIREBASE_PROJECT/g" lib/core/ai/llms/openai.dart

  # Run flutterfire configure
  echo -e "\n\033[0;32m [ ◎ ] -- Running flutterfire configure...\033[0m\n"
  flutterfire configure -o ./lib/app/configs/firebase.dart

  # GIDClientID
  echo -e "\n\033[1;34m [ ⚙︎ ] -- Google Sign-In Client IDs\033[0m\n"
  echo -e "   Find these in Firebase Console → Authentication → Sign-in method → Google\n"

  read -r -p "   iOS GIDClientID (leave empty to skip): " INIT_GID_IOS
  if [[ -n "$INIT_GID_IOS" ]]; then
    echo -e "\033[0;32m [ ◎ ] -- Updating ios/Runner/Info.plist — GIDClientID...\033[0m"
    perl -pi -e "s/\Q$_OLD_GID_CLIENT_ID_IOS\E/$INIT_GID_IOS/g" ios/Runner/Info.plist
  fi

  read -r -p "   Web google-signin-client_id (leave empty to skip): " INIT_GID_WEB
  if [[ -n "$INIT_GID_WEB" ]]; then
    echo -e "\033[0;32m [ ◎ ] -- Updating web/index.html — google-signin-client_id...\033[0m"
    perl -pi -e "s/\Q$_OLD_GID_CLIENT_ID_WEB\E/$INIT_GID_WEB/g" web/index.html
  fi

  FIREBASE_CONFIGURED=true
  echo -e "\n\033[0;32m [ ✔︎ ] -- Firebase setup complete.\033[0m"
}

init_finalize() {
  echo -e "\n\033[0;32m [ ◎ ] -- Running flutter pub get...\033[0m\n"
  fvm flutter pub get
}

init_print_checklist() {
  echo -e "\n\033[1;34m ══════════════════════════════════════════\033[0m"
  echo -e "\033[1;34m   POST-INIT CHECKLIST\033[0m"
  echo -e "\033[1;34m ══════════════════════════════════════════\033[0m\n"

  echo -e " Automated replacements complete.\n"

  if [ "$FIREBASE_CONFIGURED" = true ]; then
    echo -e " \033[1;37mFIREBASE SETUP:\033[0m \033[0;32m(configured)\033[0m"
    echo "   [✔] Firebase project configured"
    echo "   [✔] .firebaserc updated"
    echo "   [✔] firebase.json updated"
    echo "   [✔] flutterfire configure executed"
    echo "   [✔] auth.dart — socialRedirectURL"
    echo "   [✔] app.dart — storageBucket"
    echo "   [✔] openai.dart — Cloud Functions endpoint"
  else
    echo -e " \033[1;37mFIREBASE SETUP:\033[0m"
    echo "   [ ] Create Firebase project at https://console.firebase.google.com"
    echo "   [ ] Run: flutterfire configure -o ./lib/app/configs/firebase.dart"
    echo "   [ ] Update .firebaserc with your project ID"
    echo "   [ ] Update firebase.json with your app/project IDs"
    echo "   [ ] Update lib/app/configs/auth.dart -> socialRedirectURL"
    echo "   [ ] Update lib/app/configs/app.dart -> storageBucket"
    echo "   [ ] Update lib/core/ai/llms/openai.dart -> Cloud Functions endpoint"
  fi

  echo ""
  echo -e " \033[1;37mAPI KEYS:\033[0m"
  echo "   [ ] lib/app/configs/apis.dart — Google, Unsplash, OpenAI, RevenueCat"
  echo "   [ ] lib/app/configs/mailgun.dart — email service config"
  echo "   [ ] lib/app/configs/billing.dart — product identifiers"
  if [ "$FIREBASE_CONFIGURED" = true ]; then
    echo "   [✔] web/index.html — Google sign-in client ID"
    echo "   [✔] ios/Runner/Info.plist — GIDClientID"
  else
    echo "   [ ] web/index.html — Google sign-in client ID"
    echo "   [ ] ios/Runner/Info.plist — GIDClientID"
  fi
  echo ""
  echo -e " \033[1;37mBRANDING:\033[0m"
  echo "   [ ] lib/app/configs/prod.dart — store URLs, legal URLs"
  echo "   [ ] lib/app/configs/app.dart — webAppEndpoint, supportEmail"
  echo "   [ ] lib/app/configs/mailgun.dart — email addresses/domains"
  echo "   [ ] Replace icons in storage/assets/icons/"
  echo "   [ ] Run: fvm flutter pub run flutter_launcher_icons"
  echo ""
  echo -e " \033[1;37mFIREBASE DEPLOY:\033[0m"
  echo "   [ ] cd gcs && npm install"
  echo "   [ ] firebase deploy --only functions"
  echo "   [ ] firebase deploy --only firestore:rules"
  echo "   [ ] firebase deploy --only firestore:indexes"
  echo "   [ ] firebase deploy --only storage"
  echo "   [ ] firebase deploy --only remoteconfig"
  echo "   [ ] firebase deploy --only functions,firestore:indexes,firestore:rules"
  echo ""
  echo -e " \033[1;37mGIT:\033[0m"
  echo "   [ ] Commit the initialized project"
  echo ""
  echo -e "\033[1;34m ══════════════════════════════════════════\033[0m\n"
}

# ----------------------
# CHECK CONFIGS
# ----------------------
check_configs() {
  echo -e "\n\033[1;34m ══════════════════════════════════════════\033[0m"
  echo -e "\033[1;34m   CONFIG CHECK\033[0m"
  echo -e "\033[1;34m ══════════════════════════════════════════\033[0m\n"

  local PASS=0
  local WARN=0
  local FAIL=0

  _ok()   { echo -e "   \033[0;32m[✔]\033[0m $1"; ((PASS++)); }
  _warn() { echo -e "   \033[0;33m[△]\033[0m $1"; ((WARN++)); }
  _fail() { echo -e "   \033[0;31m[✖]\033[0m $1"; ((FAIL++)); }

  # Helper: check if a Dart file contains a field with an empty string value
  _dart_empty() {
    local file="$1" field="$2" label="$3"
    if [ ! -f "$file" ]; then
      _fail "$label — file not found: $file"
      return
    fi
    if grep -qE "$field\s*=\s*['\"]['\"]" "$file"; then
      _fail "$label — empty"
    else
      _ok "$label"
    fi
  }

  # Helper: check if a Dart field contains a specific placeholder
  _dart_placeholder() {
    local file="$1" pattern="$2" label="$3"
    if [ ! -f "$file" ]; then
      _fail "$label — file not found: $file"
      return
    fi
    if grep -q "$pattern" "$file"; then
      _fail "$label — still has placeholder"
    else
      _ok "$label"
    fi
  }

  # ── .appinit.conf ──
  echo -e " \033[1;37mINIT STATUS:\033[0m"
  if [ -f ".appinit.conf" ]; then
    _ok ".appinit.conf exists (project was initialized)"
  else
    _fail ".appinit.conf missing — run 'appman.sh init' first"
    echo -e "\n\033[0;31m   Cannot continue without initialization.\033[0m\n"
    return
  fi

  # ── FIREBASE ──
  echo -e "\n \033[1;37mFIREBASE:\033[0m"

  # .firebaserc
  if [ -f ".firebaserc" ]; then
    local FB_PROJECT
    FB_PROJECT=$(jq -r '.projects.default' .firebaserc 2>/dev/null)
    if [[ "$FB_PROJECT" == "app-octopoos-platform" ]]; then
      _fail ".firebaserc — still has template project ID"
    elif [[ -z "$FB_PROJECT" || "$FB_PROJECT" == "null" ]]; then
      _fail ".firebaserc — project ID is empty"
    else
      _ok ".firebaserc — project: $FB_PROJECT"
    fi
  else
    _fail ".firebaserc — file not found"
  fi

  # firebase.dart (auto-generated by flutterfire)
  local FIREBASE_DART="lib/app/configs/firebase.dart"
  if [ -f "$FIREBASE_DART" ]; then
    if grep -q "app-octopoos-platform" "$FIREBASE_DART"; then
      _fail "firebase.dart — still has template project ID (run flutterfire configure)"
    else
      _ok "firebase.dart — configured"
    fi
  else
    _fail "firebase.dart — file not found (run flutterfire configure)"
  fi

  # auth.dart — socialRedirectURL
  local AUTH_DART="lib/app/configs/auth.dart"
  _dart_placeholder "$AUTH_DART" "app-octopoos-platform" "auth.dart → socialRedirectURL"

  # app.dart — storageBucket
  local APP_DART="lib/app/configs/app.dart"
  _dart_placeholder "$APP_DART" "app-octopoos-platform" "app.dart → storageBucket"

  # openai.dart — Cloud Functions endpoint
  local OPENAI_DART="lib/core/ai/llms/openai.dart"
  _dart_placeholder "$OPENAI_DART" "app-octopoos-platform" "openai.dart → apiHost (Cloud Functions)"

  # ── API KEYS ──
  echo -e "\n \033[1;37mAPI KEYS:\033[0m"

  local APIS_DART="lib/app/configs/apis.dart"
  if [ ! -f "$APIS_DART" ]; then
    _fail "apis.dart — file not found"
  else
    _dart_empty "$APIS_DART" "iosOAuthClientID" "apis.dart → iosOAuthClientID"
    _dart_empty "$APIS_DART" "androidOAuthClientID" "apis.dart → androidOAuthClientID"
    _dart_empty "$APIS_DART" "fcmVAPID" "apis.dart → fcmVAPID"
    _dart_empty "$APIS_DART" "geminiKey" "apis.dart → geminiKey"
    _dart_empty "$APIS_DART" "googleCloudApiKey" "apis.dart → googleCloudApiKey"

    # RevenueCat — check for stub prefixes
    if grep -qE "revCatIOSKey\s*=\s*'appl_'" "$APIS_DART"; then
      _fail "apis.dart → revCatIOSKey — placeholder (appl_)"
    else
      _ok "apis.dart → revCatIOSKey"
    fi

    if grep -qE "revCatAndroidKey\s*=\s*'goog_'" "$APIS_DART"; then
      _fail "apis.dart → revCatAndroidKey — placeholder (goog_)"
    else
      _ok "apis.dart → revCatAndroidKey"
    fi

    # OpenAI
    if grep -qE "openAiKey\s*=\s*'sk-proj-'" "$APIS_DART"; then
      _fail "apis.dart → openAiKey — placeholder"
    else
      _ok "apis.dart → openAiKey"
    fi

    if grep -qE "openAiOrganizationID\s*=\s*'org-'" "$APIS_DART"; then
      _fail "apis.dart → openAiOrganizationID — placeholder"
    else
      _ok "apis.dart → openAiOrganizationID"
    fi
  fi

  # mailgun.dart
  local MAILGUN_DART="lib/app/configs/mailgun.dart"
  _dart_placeholder "$MAILGUN_DART" "octopus-apps.com" "mailgun.dart → email domain"

  # billing.dart
  local BILLING_DART="lib/app/configs/billing.dart"
  if [ ! -f "$BILLING_DART" ]; then
    _fail "billing.dart — file not found"
  else
    if grep -qE "revCatIosProIdentifier\s*=\s*\"\"" "$BILLING_DART"; then
      _fail "billing.dart → product identifiers — empty"
    else
      _ok "billing.dart → product identifiers"
    fi
  fi

  # Google Sign-In — web
  if [ -f "web/index.html" ]; then
    if grep -q "746237677326" "web/index.html"; then
      _fail "web/index.html → google-signin-client_id — template value"
    else
      _ok "web/index.html → google-signin-client_id"
    fi
  else
    _warn "web/index.html — file not found"
  fi

  # Google Sign-In — iOS
  if [ -f "ios/Runner/Info.plist" ]; then
    if grep -q "746237677326" "ios/Runner/Info.plist"; then
      _fail "Info.plist → GIDClientID — template value"
    else
      _ok "Info.plist → GIDClientID"
    fi
  else
    _warn "ios/Runner/Info.plist — file not found"
  fi

  # ── BRANDING ──
  echo -e "\n \033[1;37mBRANDING:\033[0m"

  # prod.dart
  local PROD_DART="lib/app/configs/prod.dart"
  if [ ! -f "$PROD_DART" ]; then
    _fail "prod.dart — file not found"
  else
    if grep -qE "appStoreID\s*=\s*\"\"" "$PROD_DART"; then
      _fail "prod.dart → appStoreID — empty"
    else
      _ok "prod.dart → appStoreID"
    fi

    if grep -q "octopus-apps.com" "$PROD_DART"; then
      _fail "prod.dart → legal URLs — still has template domain"
    else
      _ok "prod.dart → legal URLs"
    fi
  fi

  # app.dart — branding fields
  if grep -q "octopus-apps.com" "$APP_DART"; then
    _fail "app.dart → webAppEndpoint / supportEmail — template domain"
  else
    _ok "app.dart → webAppEndpoint / supportEmail"
  fi

  # Icons
  if grep -q '???' "$APP_DART"; then
    _fail "app.dart → logo paths — still have ??? placeholder"
  else
    _ok "app.dart → logo paths"
  fi

  # ── SUMMARY ──
  echo -e "\n\033[1;34m ──────────────────────────────────────────\033[0m"
  echo -e "   \033[0;32m$PASS passed\033[0m · \033[0;33m$WARN warnings\033[0m · \033[0;31m$FAIL failed\033[0m"
  echo -e "\033[1;34m ══════════════════════════════════════════\033[0m\n"

  if [ "$FAIL" -gt 0 ]; then
    echo -e " \033[0;33m Fill in the failed items and re-run: appman check configs\033[0m\n"
  else
    echo -e " \033[0;32m All configs look good!\033[0m\n"
  fi
}

init_project() {
  init_check_prerequisites
  init_collect_inputs
  init_confirm
  init_save_config

  echo -e "\n\033[1;34m [ ⚙︎ ] -- Applying replacements...\033[0m\n"

  init_replace_pubspec
  init_replace_android
  init_rename_android_kotlin
  init_replace_ios
  init_replace_web
  init_replace_dart_configs
  init_rename_dart_imports
  init_replace_i18n
  init_replace_docs
  init_finalize
  init_firebase_setup
  init_print_checklist
}

# ==============================================================================
# APPMAN RUNNER
# ==============================================================================

# Ensure we're in a Flutter project root (skip for commands that don't need it)
if [[ "$COMMAND" != "sync" && "$COMMAND" != "info" ]] && [ ! -f "pubspec.yaml" ]; then
  echo " [ ✖︎ ] -- pubspec.yaml not found. Run this from the project root."
  exit 1
fi

if [[ "$COMMAND" != "sync" && "$COMMAND" != "info" ]]; then
  APP_DESCRIPTION=$(grep -m1 '^description:' pubspec.yaml | sed 's/description: //')
  echo -e "\033[0;32m---------------------------------\033[0m"
  echo -e "\033[0;32m   ${APP_DESCRIPTION:-App} Manager   \033[0m"
  echo -e "\033[0;32m---------------------------------\033[0m"

  version_line=$(grep '^version:' pubspec.yaml)
  if [[ ! $version_line =~ version:\ ([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+) ]]; then
    echo " [ ✖︎ ] -- pubspec.yaml not found or malformed"
    exit 1
  fi

  export MARKETING_VERSION="${BASH_REMATCH[1]}"
  export CURRENT_PROJECT_VERSION="${BASH_REMATCH[2]}"

  bundle_line=$(grep '^bundle:' pubspec.yaml)
  if [[ ! $bundle_line =~ bundle:\ ([a-zA-Z0-9._-]+) ]]; then
    echo " [ ✖︎ ] -- bundle ID not found or malformed in pubspec.yaml"
    exit 1
  fi

  export BUNDLE_ID="${BASH_REMATCH[1]}"

  echo -e "\033[0;32m | -- BundleID → $BUNDLE_ID \033[0m"
  echo -e "\033[0;32m | -- Version → $MARKETING_VERSION \033[0m"
  echo -e "\033[0;32m | -- Build → $CURRENT_PROJECT_VERSION \033[0m"
fi

# RUNNER
# --------------------
# SYNC CLAUDE SETTINGS
# --------------------
sync_claude() {
  local SRC_DIR="$CLAUDE_SOURCE_PROJECT"

  if [[ ! -d "$SRC_DIR/.claude" ]]; then
    echo -e "\033[0;31m [ ✖︎ ] -- Source project not found: $SRC_DIR\033[0m"
    return 1
  fi

  # Discover all projects at depth 2 in FLUTTER_APPS_DIR (group/project)
  local PROJECTS=()
  local LABELS=()
  for proj_dir in "$FLUTTER_APPS_DIR"/*/*; do
    [[ ! -d "$proj_dir" ]] && continue
    [[ "$proj_dir" == "$SRC_DIR" ]] && continue
    local rel_path="${proj_dir#$FLUTTER_APPS_DIR/}"
    PROJECTS+=("$proj_dir")
    LABELS+=("$rel_path")
  done

  if [[ ${#PROJECTS[@]} -eq 0 ]]; then
    echo -e "\033[0;31m [ ✖︎ ] -- No sibling projects found.\033[0m"
    return 1
  fi

  echo -e "\n\033[1;34mSync platform Claude settings with:\033[0m\n"
  for i in "${!LABELS[@]}"; do
    echo -e "  \033[1;37m[$((i+1))]\033[0m ${LABELS[$i]}"
  done
  echo ""
  read -rp "  Select project number: " choice

  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#PROJECTS[@]} )); then
    echo -e "\033[0;31m [ ✖︎ ] -- Invalid selection.\033[0m"
    return 1
  fi

  local TARGET="${PROJECTS[$((choice-1))]}"
  local TARGET_LABEL="${LABELS[$((choice-1))]}"

  echo -e "\n\033[0;32m [ △ ] -- Syncing to: $TARGET_LABEL\033[0m\n"

  # --- Sync .claude/ (agents, skills, commands) ---
  # Exclude settings.local.json (project-specific hooks/permissions)
  mkdir -p "$TARGET/.claude"
  for subdir in agents skills commands; do
    if [[ -d "$SRC_DIR/.claude/$subdir" ]]; then
      mkdir -p "$TARGET/.claude/$subdir"
      rsync -a "$SRC_DIR/.claude/$subdir/" "$TARGET/.claude/$subdir/"
      echo -e "  \033[0;32m✓\033[0m .claude/$subdir/"
    fi
  done

  # --- Sync CLAUDE.md (preserve target header lines 1-9) ---
  local SRC_MD="$SRC_DIR/CLAUDE.md"
  local TGT_MD="$TARGET/CLAUDE.md"

  if [[ -f "$SRC_MD" ]]; then
    if [[ -f "$TGT_MD" ]]; then
      # Extract target header (lines 1 through first "## " heading)
      local header_end
      header_end=$(awk '/^## /{print NR-1; exit}' "$TGT_MD")
      header_end=${header_end:-1}
      local target_header
      target_header=$(head -n "$header_end" "$TGT_MD")

      # Extract source body (from first "## " heading to end)
      local body_start
      body_start=$(awk '/^## /{print NR; exit}' "$SRC_MD")
      if [[ -n "$body_start" ]]; then
        local source_body
        source_body=$(tail -n +"$body_start" "$SRC_MD")
        printf '%s\n%s\n' "$target_header" "$source_body" > "$TGT_MD"
      else
        cp "$SRC_MD" "$TGT_MD"
      fi
    else
      cp "$SRC_MD" "$TGT_MD"
    fi
    echo -e "  \033[0;32m✓\033[0m CLAUDE.md (header preserved)"
  fi

  echo -e "\n\033[1;32m [ ✔ ] -- Sync complete!\033[0m\n"
}

case "$COMMAND" in
    upgrade)
      upgrade_dependencies "$@"
    ;;

    release)
      # FLAGS PARSER
      for arg in "$@"; do
        case $arg in
          --all)
            RUN_IOS=true
            RUN_ANDROID=true
            RUN_WEB=true
            ;;
          --ios)
            RUN_IOS=true
            ;;
          --android)
            RUN_ANDROID=true
            ;;
          --web)
            RUN_WEB=true
            ;;
          *)
            echo " [ ✖︎ ] -- Unknown option: $arg"
            echo "Usage: $0 $COMMAND [--all|--ios|--android|--web]"
            exit 1
            ;;
        esac
      done

      # UPDATE SDK DEPS
      check_sdk_deps

      # GEN METADATA
      generate_metadata

      # IOS RELEASE
      ios_appstore_release

      # ANDROID RELEASE
      android_playstore_release

      # UPLOAD DEBUG SYMBOLS
      crashlytics_symbols_upload

      # WEB RELEASE
      webapp_firebase_release

      # CLEAR METADATA
      cleanup_metadata

      # GIT PUSH
      push_to_prod_branch

      # DEPLOY INFO
      deploy_info
    ;;

    check)
      case "${1:-tools}" in
        tools)  check_required_tools ;;
        configs) check_configs ;;
        *)
          echo " [ ✖︎ ] -- Unknown check target: $1"
          echo "Usage: $0 check [tools|configs]"
          exit 1
          ;;
      esac
    ;;

    gitall)
      # PUSH TO GIT
      push_to_prod_branch
    ;;

    version)
      # UPDATE IOS VERSION
      ios_update_version
    ;;

    validate)
      # VALIDATE API KEYS
      validate_environment
    ;;

    init)
      # INIT NEW PROJECT
      init_project
    ;;

    sync)
      case "${1:-}" in
        claude) sync_claude ;;
        *)
          echo " [ ✖︎ ] -- Unknown sync target: ${1:-}"
          echo "Usage: $0 sync claude"
          exit 1
          ;;
      esac
    ;;

    clean)
      # CLEAN APP FOLDERS
      clean_rebuild_deps
    ;;

    help)
      # SHOW HELP INFO
      show_help
    ;;

    *)
    echo " [ ✖︎ ] -- Unknown command: $COMMAND"
    exit 1
    ;;
esac