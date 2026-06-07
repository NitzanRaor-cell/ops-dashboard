#!/usr/bin/env bash
# setup-oauth.sh — One-time Google OAuth setup for the Ops Dashboard
# Requires: macOS + Homebrew  (everything else is installed automatically)
# What you have to do yourself: one browser click to approve gcloud, and
# one "Create" button in the Google Cloud Console. Everything else is automated.
set -euo pipefail

DASHBOARD_DIR="$(cd "$(dirname "$0")" && pwd)"
HTML_FILE="$DASHBOARD_DIR/index.html"
PROJECT_ID="zoomrei-ops-dashboard"
APP_NAME="ZoomREI Ops Dashboard"
REDIRECT_ORIGINS="http://localhost:8000"

# ── colours ──────────────────────────────────────────────────────────────────
G="\033[0;32m"; Y="\033[1;33m"; B="\033[0;34m"; R="\033[0;31m"; NC="\033[0m"
info()  { echo -e "${B}[info]${NC}  $*"; }
ok()    { echo -e "${G}[ok]${NC}    $*"; }
warn()  { echo -e "${Y}[warn]${NC}  $*"; }
step()  { echo -e "\n${G}▶ $*${NC}"; }

# ── 1. Install gcloud ─────────────────────────────────────────────────────────
step "Step 1 / 5 — Install gcloud CLI"
if command -v gcloud &>/dev/null; then
  ok "gcloud already installed: $(gcloud version --format='value(Google Cloud SDK)' 2>/dev/null)"
else
  info "Installing google-cloud-sdk via Homebrew..."
  brew install --cask google-cloud-sdk
  # shellcheck disable=SC1090
  source "$(brew --prefix)/share/google-cloud-sdk/path.bash.inc" 2>/dev/null || true
  ok "gcloud installed"
fi

# Make sure gcloud is on PATH
export PATH="$PATH:$(brew --prefix)/share/google-cloud-sdk/bin"

# ── 2. Authenticate ────────────────────────────────────────────────────────────
step "Step 2 / 5 — Authenticate with Google"
info "Your browser will open. Sign in with ${Y}nitzan.raor@zoomrei.com${NC} (or any ZoomREI account)."
info "Press Enter to open the browser, or Ctrl-C to abort."
read -r

gcloud auth login --quiet --brief 2>/dev/null || gcloud auth login

ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1)
ok "Authenticated as: $ACCOUNT"

# ── 3. Create / select project ────────────────────────────────────────────────
step "Step 3 / 5 — Set up Google Cloud project"
EXISTING=$(gcloud projects list --filter="projectId:$PROJECT_ID" --format='value(projectId)' 2>/dev/null || echo "")
if [[ -n "$EXISTING" ]]; then
  ok "Project $PROJECT_ID already exists"
else
  info "Creating project $PROJECT_ID..."
  gcloud projects create "$PROJECT_ID" --name="$APP_NAME" --quiet 2>/dev/null || {
    # Project ID may already be taken globally; append random suffix
    PROJECT_ID="${PROJECT_ID}-$(openssl rand -hex 3)"
    info "Retrying with id: $PROJECT_ID"
    gcloud projects create "$PROJECT_ID" --name="$APP_NAME" --quiet
  }
  ok "Created project: $PROJECT_ID"
fi
gcloud config set project "$PROJECT_ID" --quiet
ok "Active project: $PROJECT_ID"

# ── 4. Enable required APIs ───────────────────────────────────────────────────
step "Step 4 / 5 — Enable Google APIs"
APIS=(
  "oauth2.googleapis.com"
  "people.googleapis.com"
  "iamcredentials.googleapis.com"
)
for api in "${APIS[@]}"; do
  info "Enabling $api..."
  gcloud services enable "$api" --quiet 2>/dev/null || warn "$api could not be enabled (may already be on)"
done
ok "APIs enabled"

# Also configure OAuth consent screen (required before credentials can be created)
info "Configuring OAuth consent screen (internal, ZoomREI only)..."
gcloud alpha iap oauth-brands create \
  --application_title="$APP_NAME" \
  --support_email="$ACCOUNT" \
  --quiet 2>/dev/null || warn "OAuth brand already exists or could not be auto-created"

# ── 5. Create OAuth credentials ───────────────────────────────────────────────
step "Step 5 / 5 — Create OAuth 2.0 Client ID"
echo ""
echo -e "${Y}The final step requires one button click in the Google Cloud Console.${NC}"
echo ""
echo -e "  1. Your browser is about to open to the credentials page for project ${G}$PROJECT_ID${NC}"
echo -e "  2. Click  ${G}+ CREATE CREDENTIALS  →  OAuth client ID${NC}"
echo -e "  3. Application type: ${G}Web application${NC}"
echo -e "  4. Name: ${G}$APP_NAME${NC}  (or anything)"
echo -e "  5. Authorised JavaScript origins — add: ${G}$REDIRECT_ORIGINS${NC}"
echo -e "     (add more origins if hosting on GitHub Pages etc.)"
echo -e "  6. Click  ${G}CREATE${NC}  — a popup shows your Client ID"
echo -e "  7. Copy the Client ID and paste it here when prompted"
echo ""

CREDS_URL="https://console.cloud.google.com/apis/credentials/oauthclient?project=$PROJECT_ID"
info "Opening: $CREDS_URL"
open "$CREDS_URL" 2>/dev/null || xdg-open "$CREDS_URL" 2>/dev/null || echo "Open this URL: $CREDS_URL"
echo ""
read -rp "$(echo -e "${G}Paste your Client ID here:${NC} ")" CLIENT_ID

if [[ -z "$CLIENT_ID" ]]; then
  echo -e "${R}No Client ID entered. Run the script again after creating credentials.${NC}"
  exit 1
fi

# ── Update index.html ─────────────────────────────────────────────────────────
if [[ ! -f "$HTML_FILE" ]]; then
  echo -e "${R}index.html not found at $HTML_FILE${NC}"; exit 1
fi

# Replace REPLACE_WITH_YOUR_CLIENT_ID or any existing client ID value
sed -i '' "s|const GOOGLE_CLIENT_ID = '[^']*';|const GOOGLE_CLIENT_ID = '$CLIENT_ID';|" "$HTML_FILE"
ok "index.html updated with Client ID: $CLIENT_ID"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${G}════════════════════════════════════════════════════════════${NC}"
echo -e "${G}  Setup complete!${NC}"
echo ""
echo -e "  Start the dashboard:"
echo -e "  ${Y}cd ops-dashboard && python3 -m http.server 8000${NC}"
echo -e "  Then open: ${Y}http://localhost:8000${NC}"
echo ""
echo -e "  Team members sign in at: ${Y}http://localhost:8000${NC}"
echo -e "  with their @zoomrei.com Google account."
echo ""
echo -e "  To allow more origins later (GitHub Pages, etc.):"
echo -e "  ${Y}https://console.cloud.google.com/apis/credentials?project=$PROJECT_ID${NC}"
echo -e "${G}════════════════════════════════════════════════════════════${NC}"
