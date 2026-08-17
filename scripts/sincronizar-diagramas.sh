#!/usr/bin/env bash
# Copia la fuente de cada diagrama (diagramas/*.mmd) dentro de los .md que lo referencian.
#
# En un .md, un diagrama se marca así:
#
#   <!-- mmd:03-capas-android.mmd -->
#   ```mermaid
#   ...contenido que este script reemplaza...
#   ```
#
# Uso: scripts/sincronizar-diagramas.sh        (desde la raíz del repo)
# Idempotente: si nada cambió, no toca los archivos.
set -euo pipefail
cd "$(dirname "$0")/.."

cambiados=0
for md in README.md README.en.md docs/*.md; do
  [ -f "$md" ] || continue
  tmp="$(mktemp)"
  awk '
    function leer(nombre,   linea, contenido, ruta) {
      ruta = "diagramas/" nombre
      contenido = ""
      while ((getline linea < ruta) > 0) contenido = contenido linea "\n"
      close(ruta)
      if (contenido == "") { print "ERROR: no existe " ruta > "/dev/stderr"; exit 1 }
      return contenido
    }
    /^<!-- mmd:[^ ]+ -->$/ {
      match($0, /mmd:[^ ]+/); nombre = substr($0, RSTART + 4, RLENGTH - 4)
      print; esperando = 1; next
    }
    esperando && /^```mermaid$/ { print; printf "%s", leer(nombre); dentro = 1; esperando = 0; next }
    dentro && /^```$/ { dentro = 0; print; next }
    dentro { next }
    { print }
  ' "$md" > "$tmp"
  if ! cmp -s "$md" "$tmp"; then
    mv "$tmp" "$md"; echo "actualizado: $md"; cambiados=$((cambiados + 1))
  else
    rm -f "$tmp"
  fi
done
echo "listo ($cambiados archivo(s) actualizado(s))"
