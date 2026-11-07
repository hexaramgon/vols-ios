#!/bin/bash
# Make sure the app is signed in, using the App Review demo account
# (@lowkeyloops) unless DEMO_EMAIL / DEMO_PASSWORD are set. Credentials live
# outside the repo in ~/.config/volspire/demo.env (override with DEMO_ENV).
# Needs the app running and the driver started. No-op when already signed in.
source "$(dirname "$0")/env.sh"
DRV="$SKILL_DIR/scripts/drv.sh"
[ -f "${DEMO_ENV:-$HOME/.config/volspire/demo.env}" ] && source "${DEMO_ENV:-$HOME/.config/volspire/demo.env}"
[ -n "$DEMO_EMAIL" ] && [ -n "$DEMO_PASSWORD" ] || { echo "no demo credentials (set DEMO_EMAIL/DEMO_PASSWORD or create ~/.config/volspire/demo.env)"; exit 1; }

screen=$("$DRV" "activate" "wait 1" "labels")
if ! grep -q "Welcome back" <<<"$screen"; then
  # The Welcome screen: a "Sign in" button next to "Create account".
  if grep -q $'\tSign in\t' <<<"$screen" && grep -q $'\tCreate account\t' <<<"$screen"; then
    screen=$("$DRV" "tap Sign in" "wait 1.5" "labels")
  else
    echo "already signed in"; exit 0
  fi
fi

# The login fields have no labels: find them by element type (49 text field, 50 secure field).
center() { awk -F'\t' -v t="$1" '$1==t { split($2,a,"[,x]"); printf "%d %d", a[1]+a[3]/2, a[2]+a[4]/2; exit }' <<<"$screen"; }
email_xy=$(center 49); pass_xy=$(center 50)
[ -n "$email_xy" ] && [ -n "$pass_xy" ] || { echo "login fields not found"; exit 1; }

"$DRV" "tapxy $email_xy" "wait 0.5" "type $DEMO_EMAIL" "tapxy $pass_xy" "wait 0.5" "type $DEMO_PASSWORD" "tap Sign In" "wait 5" >/dev/null
after=$("$DRV" "labels")
if grep -q "Welcome back" <<<"$after"; then
  echo "sign-in failed — still on the login screen:"; grep -iE "error|invalid|wrong|incorrect" <<<"$after"; exit 1
fi
# iOS offers to save the password after a typed login — dismiss it.
grep -q "Save Password" <<<"$after" && "$DRV" "tap Not Now" "wait 1" >/dev/null
echo "signed in as $DEMO_EMAIL"
