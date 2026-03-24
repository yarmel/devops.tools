#!/bin/bash

# ============================================================
# calipso.sh — bulk operations across Flutter projects
# Usage: ./calipso.sh <command> [subcommand] [args...]
# ============================================================

APPS_DIR="$HOME/Projects/Flutter/Apps"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# -----------------------------------------------------------
# Helpers
# -----------------------------------------------------------

print_header() {
  echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}  calipso — $1${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_project() {
  echo -e "${GREEN} [ △ ] ${1}${NC}"
}

print_skip() {
  echo -e "${YELLOW} [ — ] ${1} (skipped: ${2})${NC}"
}

print_error() {
  echo -e "${RED} [ ✗ ] ${1}${NC}"
}

print_done() {
  echo -e "\n${GREEN} [ ✓ ] All done.${NC}\n"
}

# -----------------------------------------------------------
# find_flutter_projects — scan APPS_DIR for Flutter projects
# Returns list of dirs containing both pubspec.yaml and .git
# -----------------------------------------------------------

find_flutter_projects() {
  find "$APPS_DIR" -maxdepth 3 -name "pubspec.yaml" -print0 2>/dev/null | while IFS= read -r -d '' pubspec; do
    local dir
    dir=$(dirname "$pubspec")
    if [[ -d "$dir/.git" ]]; then
      echo "$dir"
    fi
  done
}

# -----------------------------------------------------------
# mass — run a command in every project
# -----------------------------------------------------------

cmd_mass() {
  local subcmd="$1"
  shift

  case "$subcmd" in
    gitall)   mass_gitall "$@" ;;
    clean)    mass_clean "$@" ;;
    *)
      echo -e "${RED}Unknown mass subcommand: ${subcmd}${NC}"
      echo "Available: gitall, clean"
      exit 1
      ;;
  esac
}

mass_gitall() {
  local message="${1:-Bugfix & performance improvements}"

  print_header "mass gitall → '$message'"

  local projects
  projects=$(find_flutter_projects)

  if [[ -z "$projects" ]]; then
    echo -e "${YELLOW}No Flutter projects with git found in ${APPS_DIR}${NC}"
    return 1
  fi

  while IFS= read -r project_dir; do
    local relative
    relative="${project_dir#$APPS_DIR/}"

    print_project "$relative"

    cd "$project_dir" || continue
    git add .
    git commit -m "$message"
    git push origin production

    if [[ $? -eq 0 ]]; then
      echo -e "  pushed ✓"
    else
      print_error "$relative — push failed"
    fi
  done <<< "$projects"

  print_done
}

mass_clean() {
  print_header "mass flutter clean"

  local projects
  projects=$(find_flutter_projects)

  if [[ -z "$projects" ]]; then
    echo -e "${YELLOW}No Flutter projects found in ${APPS_DIR}${NC}"
    return 1
  fi

  while IFS= read -r project_dir; do
    local relative
    relative="${project_dir#$APPS_DIR/}"

    print_project "$relative"

    cd "$project_dir" || continue
    fvm flutter clean
    fvm flutter pub get
    fvm flutter pub upgrade

    if [[ $? -eq 0 ]]; then
      echo -e "  done ✓"
    else
      print_error "$relative — failed"
    fi
  done <<< "$projects"

  print_done
}

# -----------------------------------------------------------
# Routing
# -----------------------------------------------------------

main() {
  local command="$1"
  shift

  case "$command" in
    mass)   cmd_mass "$@" ;;
    *)
      echo -e "${CYAN}Usage:${NC} ./calipso.sh <command> [subcommand] [args...]"
      echo ""
      echo "Commands:"
      echo "  mass gitall [message]   — git add/commit/push production in all projects"
      echo "  mass clean              — fvm flutter clean in all projects"
      echo ""
      exit 1
      ;;
  esac
}

main "$@"