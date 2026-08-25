#!/bin/bash
# Audit de pre-diffusion (Developer ID + notarisation).
#
# Rejoue les verifications qui ont mordu au moins une fois pendant le
# developpement, plus celles que la notarisation refuse. A relancer avant
# chaque archive.
#
# NOTE : RSnotch n'est plus une app du Mac App Store (voir docs/Distribution.md).
# Les controles specifiques au bac a sable ont donc change de sens — c'est
# desormais son ABSENCE qui est attendue.
#
# Usage : Tools/preflight.sh [chemin/vers/RSnotch.app]

set -uo pipefail
cd "$(dirname "$0")/.."

APP="${1:-$HOME/Library/Developer/Xcode/DerivedData/RSnotch-edwskiygqfcxnbbhpepewqksjpxz/Build/Products/Release/RSnotch.app}"
fail=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; fail=1; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }

echo "== Code source =="
# Hors App Store, les API privees ne sont plus interdites — mais elles doivent
# rester CONFINEES a BrightnessControl.swift, qui les resout a l'execution et
# sait echouer proprement. Ailleurs, c'est une regression.
leaks=$(grep -rlE "dlsym|DisplayServices|MediaRemote|CGSCopy|SkyLight" RSnotch --include="*.swift" \
        | grep -v "BrightnessControl.swift" \
        | xargs grep -lE "dlsym\(|DisplayServicesSetBrightness|DisplayServicesGetBrightness" 2>/dev/null \
        | wc -l | tr -d ' ')
[ "$leaks" = "0" ] \
    && ok "API privées confinées à BrightnessControl.swift" \
    || bad "$leaks fichier(s) hors BrightnessControl utilisent des symboles privés"

sel=$(grep -rn 'Selector((' RSnotch --include="*.swift" | wc -l | tr -d ' ')
[ "$sel" = "0" ] && ok "aucun sélecteur construit par chaîne" || warn "$sel sélecteur(s) par chaîne — à justifier"

echo "== Bundle : $APP =="
[ -d "$APP" ] || { bad "bundle introuvable — lancer un build Release d'abord"; exit 1; }

plist="$APP/Contents/Info.plist"
for key in LSApplicationCategoryType LSUIElement NSAppleEventsUsageDescription \
           NSBluetoothAlwaysUsageDescription CFBundleShortVersionString CFBundleVersion \
           ITSAppUsesNonExemptEncryption NSHumanReadableCopyright; do
    if /usr/libexec/PlistBuddy -c "Print :$key" "$plist" >/dev/null 2>&1; then
        ok "Info.plist : $key"
    else
        bad "Info.plist : $key MANQUANT"
    fi
done

# Le manifeste n'est plus exige (il l'est par App Store Connect, pas par la
# notarisation) mais il est conserve : il documente honnetement ce que l'app
# touche, et redeviendra obligatoire si la distribution change encore.
[ -f "$APP/Contents/Resources/PrivacyInfo.xcprivacy" ] \
    && ok "manifeste de confidentialité présent" \
    || warn "PrivacyInfo.xcprivacy absent (non bloquant hors App Store)"

[ -f "$APP/Contents/Resources/AppIcon.icns" ] \
    && ok "icône compilée" \
    || bad "AppIcon.icns absent"

echo "== Frameworks liés =="
priv=$(otool -L "$APP/Contents/MacOS/RSnotch" | grep -iE "PrivateFrameworks" | wc -l | tr -d ' ')
[ "$priv" = "0" ] && ok "aucun PrivateFramework lié" || bad "$priv framework(s) privé(s) liés"

echo "== Signature =="
siginfo=$(codesign -dvvv "$APP" 2>&1)
codesign --verify --deep --strict "$APP" 2>/dev/null && ok "signature valide" || bad "signature invalide"
# La sortie est capturee AVANT d'etre filtree : `grep -q` ferme le tube des la
# premiere correspondance, ce qui tue `codesign` par SIGPIPE et, sous
# `pipefail`, fait echouer la verification alors qu'elle a reussi.
echo "$siginfo" | grep -q "flags=.*runtime" && ok "Hardened Runtime actif" || bad "Hardened Runtime absent"

ents=$(codesign -d --entitlements :- "$APP" 2>/dev/null)
# Le bac a sable doit etre ABSENT : il empeche CGEventTap, donc l'interception
# des touches, qui est la raison d'etre de la distribution hors App Store.
if echo "$ents" | grep -q "com.apple.security.app-sandbox"; then
    bad "App Sandbox présent : il bloquera CGEventTap et l'interception des touches"
else
    ok "App Sandbox absent (requis pour l'interception)"
fi

echo "$ents" | grep -q "automation.apple-events" \
    && ok "apple-events présent (requis sous Hardened Runtime)" \
    || bad "automation.apple-events absent : les Apple Events seront refusés"

if echo "$siginfo" | grep -q "Developer ID Application"; then
    ok "signé Developer ID Application"
else
    warn "pas signé Developer ID : la notarisation refusera cette build"
fi

if echo "$ents" | grep -q "get-task-allow"; then
    warn "get-task-allow présent : normal en Debug, doit disparaître de la build diffusée"
else
    ok "get-task-allow absent"
fi

echo
[ "$fail" = "0" ] && echo "Préflight OK." || echo "Préflight EN ÉCHEC : corriger les ✗ avant d'archiver."
exit $fail
