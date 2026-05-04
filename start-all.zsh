#!/usr/bin/env zsh
# Lance les 4 services (mfe-product, mfe-cart, mfe-reco, shell) en parallèle.
# Version zsh idiomatique pour macOS (zsh par défaut depuis Catalina).
# Ctrl+C tue tout proprement.

emulate -L zsh
setopt err_return no_unset pipe_fail

ROOT="${0:A:h}"
LOG_DIR="${ROOT}/.logs"
mkdir -p "${LOG_DIR}"

# (nom port couleur) — zsh: arrays associatifs ordonnés via deux tableaux parallèles.
typeset -a SERVICES=(mfe-product mfe-cart mfe-reco shell)
typeset -A PORTS=(mfe-product 3001 mfe-cart 3002 mfe-reco 3003 shell 3000)
typeset -A COLORS=(
  mfe-product $'\e[36m'   # cyan
  mfe-cart    $'\e[32m'   # vert
  mfe-reco    $'\e[35m'   # magenta
  shell       $'\e[33m'   # jaune
)
RESET=$'\e[0m'
BOLD=$'\e[1m'

typeset -a PIDS=()

cleanup() {
  print
  print -P "%B→ Arrêt des services…%b"
  for pid in $PIDS; do
    if kill -0 $pid 2>/dev/null; then
      # -pid = process group (job control activé via setopt monitor dans le subshell)
      kill -TERM -- -$pid 2>/dev/null || kill $pid 2>/dev/null
    fi
  done
  wait 2>/dev/null
  print -P "%B→ Stoppé.%b"
  exit 0
}
trap cleanup INT TERM

# Vérifie & installe les deps si node_modules manque.
for name in $SERVICES; do
  if [[ ! -d "${ROOT}/${name}/node_modules" ]]; then
    print -P "%B→ npm install pour ${name}…%b"
    (cd "${ROOT}/${name}" && npm install --silent) || {
      print "✗ npm install a échoué pour ${name}" >&2
      exit 1
    }
  fi
done

print
print -P "%B→ Démarrage des micro-frontends%b"
for name in $SERVICES; do
  print "  • ${name}:${PORTS[$name]}"
done
print

# Lance chaque service en arrière-plan. setopt monitor → process group dédié,
# nécessaire pour que kill -TERM -<pid> tue webpack-dev-server proprement.
for name in $SERVICES; do
  port=${PORTS[$name]}
  color=${COLORS[$name]}

  (
    setopt monitor
    cd "${ROOT}/${name}"
    npm start 2>&1 | while IFS= read -r line; do
      printf '%s[%s:%s]%s %s\n' "$color" "$name" "$port" "$RESET" "$line"
    done
  ) &
  PIDS+=($!)
done

print
print -P "%B→ Tous les services lancés. Ouvrez http://localhost:3000%b"
print -P "%B→ Ctrl+C pour tout arrêter.%b"
print

# Surveille : si un service meurt, on stoppe le reste.
while true; do
  for pid in $PIDS; do
    if ! kill -0 $pid 2>/dev/null; then
      print
      print -P "%B✗ Un service s'est arrêté (pid ${pid}). Nettoyage.%b"
      cleanup
    fi
  done
  sleep 2
done
