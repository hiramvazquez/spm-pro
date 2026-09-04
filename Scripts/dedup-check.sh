#!/usr/bin/env bash
# Scripts/dedup-check.sh — algunos scripts de CI existen por duplicado porque cada paquete
# necesita su propia copia REAL (no un symlink) para que sobreviva al `git subtree split
# --prefix=<paquete>` que publica AppFoundation/ y CoreNetworking/ como repos propios: un
# symlink que apunte fuera del subdirectorio publicado no resolvería nada en el repo
# resultante. Eso convierte cada copia en texto mantenido a mano, y una copia que diverge en
# silencio (nadie se entera hasta que el CI del repo publicado se comporta distinto al del
# monorepo) es peor que la duplicación en sí. Este script hace la deriva ruidosa: falla si
# alguna copia que DEBE ser idéntica no lo es.
#
# - `check-doc-snippets.sh`: idéntico en Scripts/, AppFoundation/Scripts/ y
#   CoreNetworking/Scripts/ — no hay razón para que difiera entre paquetes.
# - `verify-generator.sh`: idéntico entre Scripts/ y AppFoundation/Scripts/ SALVO la sección
#   delimitada por los comentarios `SOLO-APPFOUNDATION: begin` / `SOLO-APPFOUNDATION: end`
#   (PRD-AF-10, "modo multi"): esa sección es cobertura adicional que solo corre en el CI del
#   repo publicado de AppFoundation (job `multi`; el monorepo no lo tiene). Fuera de esa
#   sección, un cambio en una copia sin el mismo cambio en la otra es una regresión real: el
#   generador dejaría de probarse igual en ambos CI.
#
# Uso: Scripts/dedup-check.sh   (desde la raíz del repo; falla con diff si algo diverge)
# CI: .github/workflows/ci.yml, job `dedup-check`.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

status=0

log()  { printf '\n\033[1;34m▶ %s\033[0m\n' "$1"; }
warn() { printf '\033[1;31m✘ %s\033[0m\n' "$1" >&2; status=1; }

log "check-doc-snippets.sh idéntico en los tres paquetes"
for pkg in AppFoundation CoreNetworking; do
    if ! diff -u Scripts/check-doc-snippets.sh "$pkg/Scripts/check-doc-snippets.sh"; then
        warn "Scripts/check-doc-snippets.sh y $pkg/Scripts/check-doc-snippets.sh divergieron — sincronízalos"
    fi
done

log "verify-generator.sh idéntico entre Scripts/ y AppFoundation/Scripts/ (fuera de SOLO-APPFOUNDATION)"
stripped="$(mktemp)"
trap 'rm -f "$stripped"' EXIT
sed '/SOLO-APPFOUNDATION: begin/,/SOLO-APPFOUNDATION: end/d' AppFoundation/Scripts/verify-generator.sh > "$stripped"
if ! diff -u Scripts/verify-generator.sh "$stripped"; then
    warn "Scripts/verify-generator.sh y AppFoundation/Scripts/verify-generator.sh divergieron fuera de la sección SOLO-APPFOUNDATION — sincronízalos (o marca el trozo nuevo como SOLO-APPFOUNDATION si es cobertura que de verdad solo aplica allí)"
fi

if [ "$status" -eq 0 ]; then
    log "Sin deriva: las copias que deben coincidir, coinciden"
else
    printf '\n\033[1;31m✘ Hay copias divergentes — ver diffs arriba\033[0m\n' >&2
fi
exit "$status"
