#!/bin/bash

# ============================================================
# iconify.sh — generate app icons via OpenAI GPT-4o
# Usage: ./iconify.sh
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLES_DIR="$SCRIPT_DIR/.samples"
OUTPUT_DIR="$(pwd)"
API_URL="https://api.openai.com/v1/chat/completions"
ICON_PREFIX="app-icon-flow"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# -----------------------------------------------------------
# Preflight
# -----------------------------------------------------------

if [[ -z "$OPENAI_API_KEY" ]]; then
  echo -e "${RED}Error: OPENAI_API_KEY is not set.${NC}"
  echo "Add it to ~/.zshrc:  export OPENAI_API_KEY=\"sk-...\""
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo -e "${RED}Error: jq is required. Install with: brew install jq${NC}"
  exit 1
fi

# Encode sample icon sheets as base64
SAMPLE1="$SAMPLES_DIR/s1.jpg"
SAMPLE2="$SAMPLES_DIR/s2.jpg"

if [[ ! -f "$SAMPLE1" || ! -f "$SAMPLE2" ]]; then
  echo -e "${RED}Error: sample icon sheets not found in $SAMPLES_DIR${NC}"
  exit 1
fi

S1_B64=$(base64 < "$SAMPLE1")
S2_B64=$(base64 < "$SAMPLE2")

# Find next version number based on existing files
LAST_VERSION=$(ls -1 "$OUTPUT_DIR"/${ICON_PREFIX}-v*.png 2>/dev/null \
  | sed -E "s/.*${ICON_PREFIX}-v([0-9]+)\.png/\1/" \
  | sort -n | tail -1)
NEXT_VERSION=$(( ${LAST_VERSION:-0} + 1 ))

# -----------------------------------------------------------
# Collect input
# -----------------------------------------------------------

echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  iconify — AI app icon generator${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# Keywords
echo -e "${BOLD}Keywords${NC} (describe the central figure/visual):"
read -rp "> " KEYWORDS

if [[ -z "$KEYWORDS" ]]; then
  echo -e "${RED}Keywords cannot be empty.${NC}"
  exit 1
fi

# Background color
echo -e "\n${BOLD}Background color${NC} (e.g. #1A1A2E, dark blue, white):"
read -rp "> " BG_COLOR
BG_COLOR="${BG_COLOR:-white}"

# Gradient
echo -e "\n${BOLD}Use gradient background?${NC} (y/n):"
read -rp "> " USE_GRADIENT
if [[ "$USE_GRADIENT" =~ ^[yY] ]]; then
  GRADIENT_TEXT="with a smooth gradient background based on $BG_COLOR"
else
  GRADIENT_TEXT="with a solid $BG_COLOR background"
fi

# Style
echo -e "\n${BOLD}Icon style:${NC}"
echo "  1) Flat / Minimal"
echo "  2) 3D / Glossy"
echo "  3) Skeuomorphic"
echo "  4) Line Art / Outline"
echo "  5) Neon Glow"
echo "  6) Watercolor"
echo "  7) Pixel Art"
echo "  8) Clay / 3D Render"
read -rp "> " STYLE_CHOICE

case "$STYLE_CHOICE" in
  1) STYLE="flat minimal clean" ;;
  2) STYLE="3D glossy shiny with reflections" ;;
  3) STYLE="skeuomorphic realistic textured" ;;
  4) STYLE="line art thin outline monochrome" ;;
  5) STYLE="neon glow dark background vibrant light" ;;
  6) STYLE="watercolor soft artistic hand-painted" ;;
  7) STYLE="pixel art retro 8-bit" ;;
  8) STYLE="clay 3D render soft lighting plasticine" ;;
  *)
    echo -e "${RED}Invalid choice, defaulting to Flat / Minimal${NC}"
    STYLE="flat minimal clean"
    ;;
esac

# Quantity
echo -e "\n${BOLD}How many icons to generate?${NC} (1-10):"
read -rp "> " COUNT
COUNT="${COUNT:-1}"

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [[ "$COUNT" -lt 1 ]] || [[ "$COUNT" -gt 10 ]]; then
  echo -e "${RED}Invalid number, defaulting to 1${NC}"
  COUNT=1
fi

# -----------------------------------------------------------
# Build prompt
# -----------------------------------------------------------

PROMPT="A single flat 1024x1024 square image. NOT an app icon mockup — just a plain illustration. The background ($GRADIENT_TEXT) fills the entire canvas from edge to edge. On top of this background, place the subject: $KEYWORDS — centered, occupying about 60% of the canvas. The subject sits directly on the background with no card, no frame, no rounded rectangle, no shadow, no 3D floating effect, no border, no margin. Think of it as a seamless wallpaper with a centered motif. Style: $STYLE. No text, no letters, no words anywhere."

echo -e "\n${CYAN}Prompt:${NC} $PROMPT"
echo -e "${CYAN}Generating $COUNT icon(s)...${NC}\n"

# -----------------------------------------------------------
# Generate
# -----------------------------------------------------------

SUCCESS=0
FAIL=0
VERSION=$NEXT_VERSION

for i in $(seq 1 "$COUNT"); do
  echo -e "${YELLOW} [$i/$COUNT] Generating...${NC}"

  RESPONSE=$(curl -s "$API_URL" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -d "$(jq -n \
      --arg model "dall-e-3" \
      --arg prompt "$PROMPT" \
      --arg size "1024x1024" \
      --arg quality "hd" \
      --arg n "1" \
      '{model: $model, prompt: $prompt, size: $size, quality: $quality, n: ($n | tonumber)}'
    )")

  # Check for error
  ERROR=$(echo "$RESPONSE" | jq -r '.error.message // empty')
  if [[ -n "$ERROR" ]]; then
    echo -e "${RED} [ ✗ ] API error: $ERROR${NC}"
    ((FAIL++))
    continue
  fi

  # Extract URL
  IMAGE_URL=$(echo "$RESPONSE" | jq -r '.data[0].url // empty')
  if [[ -z "$IMAGE_URL" ]]; then
    echo -e "${RED} [ ✗ ] No image URL in response${NC}"
    ((FAIL++))
    continue
  fi

  # Download
  FILENAME="${ICON_PREFIX}-v${VERSION}.png"
  FILEPATH="$OUTPUT_DIR/$FILENAME"

  if curl -s "$IMAGE_URL" -o "$FILEPATH"; then
    echo -e "${GREEN} [ ✓ ] Saved: $FILENAME${NC}"
    ((SUCCESS++))
    ((VERSION++))
  else
    echo -e "${RED} [ ✗ ] Download failed${NC}"
    ((FAIL++))
  fi
done

# -----------------------------------------------------------
# Summary
# -----------------------------------------------------------

echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN} ✓ $SUCCESS generated${NC}  ${RED}✗ $FAIL failed${NC}"
echo -e "${CYAN} Output: $OUTPUT_DIR${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
