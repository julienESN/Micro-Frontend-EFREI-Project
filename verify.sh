#!/usr/bin/env bash
# Preuve que les 4 services tournent simultanément.
# Vérifie en parallèle que chaque endpoint répond 200 et expose le bon contenu :
#   - shell:3000        -> HTML
#   - mfe-product:3001  -> remoteEntry.js (Module Federation)
#   - mfe-cart:3002     -> remoteEntry.js
#   - mfe-reco:3003     -> remoteEntry.js
# Code de sortie : 0 si tout est OK, 1 sinon.

set -u

CHECKS=(
  "shell|http://localhost:3000/|html"
  "mfe-product|http://localhost:3001/remoteEntry.js|remote"
  "mfe-cart|http://localhost:3002/remoteEntry.js|remote"
  "mfe-reco|http://localhost:3003/remoteEntry.js|remote"
)

GREEN=$'\033[32m'
RED=$'\033[31m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo -e "${BOLD}→ Vérification parallèle des 4 services à $(date '+%H:%M:%S')${RESET}"
echo ""

# Lance les 4 checks en parallèle, chacun écrit son résultat dans un fichier.
for entry in "${CHECKS[@]}"; do
  IFS='|' read -r name url kind <<< "$entry"
  (
    start=$(date +%s%N)
    body_file="${TMP}/${name}.body"
    code=$(curl -s -o "${body_file}" -w "%{http_code}" --max-time 5 "${url}" || echo "000")
    end=$(date +%s%N)
    ms=$(( (end - start) / 1000000 ))
    bytes=$(wc -c < "${body_file}" | tr -d ' ')

    # Vérification du contenu attendu.
    content_ok="no"
    if [[ "${kind}" == "html" ]]; then
      if grep -qi "<html" "${body_file}" 2>/dev/null; then content_ok="yes"; fi
    else
      # remoteEntry.js doit contenir une signature MF (var <name> = ... __webpack_require__).
      if grep -q "webpackChunk\|__webpack_require__\|var ${name//-/_}" "${body_file}" 2>/dev/null \
         || head -c 200 "${body_file}" | grep -q "var "; then
        content_ok="yes"
      fi
    fi

    printf "%s|%s|%s|%s|%s\n" "${name}" "${code}" "${ms}" "${bytes}" "${content_ok}" \
      > "${TMP}/${name}.result"
  ) &
done
wait

# Tableau de résultats.
printf "%-14s %-8s %-12s %-12s %-12s %s\n" \
  "SERVICE" "HTTP" "TEMPS" "TAILLE" "CONTENU" "VERDICT"
printf "%s\n" "──────────────────────────────────────────────────────────────────────"

ok=0
ko=0
for entry in "${CHECKS[@]}"; do
  IFS='|' read -r name _ _ <<< "$entry"
  IFS='|' read -r n code ms bytes content_ok < "${TMP}/${name}.result"

  if [[ "${code}" == "200" && "${content_ok}" == "yes" ]]; then
    verdict="${GREEN}✓ OK${RESET}"
    ok=$((ok + 1))
  else
    verdict="${RED}✗ KO${RESET}"
    ko=$((ko + 1))
  fi

  printf "%-14s %-8s %-12s %-12s %-12s %b\n" \
    "${n}" "${code}" "${ms}ms" "${bytes}o" "${content_ok}" "${verdict}"
done

echo ""
if [[ ${ko} -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}✓ Les 4 services répondent simultanément.${RESET}"
  echo -e "${DIM}Preuve datée : $(date -u '+%Y-%m-%dT%H:%M:%SZ')${RESET}"
  exit 0
else
  echo -e "${RED}${BOLD}✗ ${ko}/${#CHECKS[@]} service(s) en échec.${RESET}"
  exit 1
fi
