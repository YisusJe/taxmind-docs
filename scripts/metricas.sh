#!/usr/bin/env bash
# Calcula las métricas de "TaxMind en números" a partir de los repos locales de código
# y las imprime como tabla Markdown para pegarla en el README.
#
# Uso (desde la raíz de esta carpeta):
#   scripts/metricas.sh [RUTA_APP] [RUTA_SITIO] [RUTA_ADMIN]
#   scripts/metricas.sh --escribir      # además reemplaza la tabla en README.md y README.en.md
#
# Por defecto busca los repos como hermanos de esta carpeta:
#   ../ia contadores            (app Android + supabase/)
#   ../Taxmind Website/taxmind-website
#   ../taxmind-admin
# o en las variables TAXMIND_APP, TAXMIND_SITIO, TAXMIND_ADMIN.
#
# Sólo cuenta archivos y líneas de código; nunca consulta la base de datos.
set -euo pipefail

aqui="$(cd "$(dirname "$0")/.." && pwd)"
escribir=0
args=()
for a in "$@"; do
  case "$a" in
    --escribir) escribir=1 ;;
    *) args+=("$a") ;;
  esac
done

APP="${args[0]:-${TAXMIND_APP:-$aqui/../ia contadores}}"
SITIO="${args[1]:-${TAXMIND_SITIO:-$aqui/../Taxmind Website/taxmind-website}}"
ADMIN="${args[2]:-${TAXMIND_ADMIN:-$aqui/../taxmind-admin}}"

for d in "$APP" "$SITIO" "$ADMIN"; do
  [ -d "$d" ] || { echo "No existe: $d" >&2; exit 1; }
done

# --- helpers ---------------------------------------------------------------
contar_archivos() { # dir, patrón find (-name), excluir build/node_modules/.git
  find "$1" \( -path '*/node_modules' -o -path '*/build' -o -path '*/.git' -o -path '*/dist' -o -path '*/.astro' \) -prune -o -type f -name "$2" -print 2>/dev/null | wc -l | tr -d ' '
}
lineas() { # dir, patrón
  find "$1" \( -path '*/node_modules' -o -path '*/build' -o -path '*/.git' -o -path '*/dist' -o -path '*/.astro' \) -prune -o -type f -name "$2" -print0 2>/dev/null \
    | xargs -0 cat 2>/dev/null | wc -l | tr -d ' '
}
miles() { # separador de miles con punto (es-VE)
  printf '%s' "$1" | sed ':a;s/\B[0-9]\{3\}\>/.&/;ta'
}
commits() { git -C "$1" rev-list --count HEAD 2>/dev/null || echo 0; }
primer_commit() { git -C "$1" log --reverse --format=%ad --date=short 2>/dev/null | head -1; }

# --- app + backend ---------------------------------------------------------
migraciones=$(ls "$APP/supabase/migrations"/*.sql 2>/dev/null | wc -l | tr -d ' ')
tablas=$(grep -hoiE 'create table (if not exists )?public\.[a-z_]+' "$APP"/supabase/migrations/*.sql 2>/dev/null \
  | sed -E 's/.*public\.//' | sort -u | wc -l | tr -d ' ')
# tablas eliminadas después (drop table) se restan para dar las vivas
tablas_drop=$(grep -hoiE 'drop table (if exists )?public\.[a-z_]+' "$APP"/supabase/migrations/*.sql 2>/dev/null \
  | sed -E 's/.*public\.//' | sort -u | wc -l | tr -d ' ')
tablas_vivas=$((tablas - tablas_drop))
functions=$(find "$APP/supabase/functions" -mindepth 1 -maxdepth 1 -type d ! -name '_*' 2>/dev/null | wc -l | tr -d ' ')
# los inserts ocupan varias líneas: se toman las 4 siguientes y se cuenta el primer literal (id)
buckets=$(grep -hiA4 "insert into storage\.buckets" "$APP"/supabase/migrations/*.sql 2>/dev/null \
  | grep -oE "^ *(values *)?\( *'[a-z-]+'|^ *'[a-z-]+',$" | grep -oE "'[a-z-]+'" | sort -u | wc -l | tr -d ' ')
screens=$(contar_archivos "$APP/app/src/main" '*Screen.kt')
viewmodels=$(contar_archivos "$APP/app/src/main" '*ViewModel.kt')
tests_jvm=$(contar_archivos "$APP/app/src/test" '*Test.kt')
tests_deno=$(contar_archivos "$APP/supabase/functions" '*_test.ts')
tests_e2e=$(ls "$APP"/scripts/test_*.sh 2>/dev/null | wc -l | tr -d ' ')
version=$(grep -oE 'versionName *= *"[^"]+"' "$APP/app/build.gradle.kts" | sed -E 's/.*"([^"]+)"/\1/')
loc_kt=$(lineas "$APP/app/src" '*.kt')
loc_sql=$(lineas "$APP/supabase/migrations" '*.sql')
loc_ts_fn=$(lineas "$APP/supabase/functions" '*.ts')

# --- sitio + admin ---------------------------------------------------------
paginas=$(contar_archivos "$SITIO/src/pages" '*.astro')
componentes=$(contar_archivos "$SITIO/src/components" '*.astro')
# vistas del admin: un componente Pagina*.tsx por vista (sin la de "no encontrado")
modulos_admin=$(find "$ADMIN/src" -type f -name 'Pagina*.tsx' ! -name 'PaginaEnConstruccion.tsx' 2>/dev/null | wc -l | tr -d ' ')
loc_astro=$(lineas "$SITIO/src" '*.astro')
loc_ts_admin=$(( $(lineas "$ADMIN/src" '*.ts') + $(lineas "$ADMIN/src" '*.tsx') ))

# --- git -------------------------------------------------------------------
c_app=$(commits "$APP"); c_sitio=$(commits "$SITIO"); c_admin=$(commits "$ADMIN")
commits_total=$((c_app + c_sitio + c_admin))
primero="$(primer_commit "$APP")"
fecha="$(date +%Y-%m-%d)"

# --- tabla -----------------------------------------------------------------
tabla_es=$(cat <<EOF
| Métrica | Valor |
|---|---|
| Migraciones SQL | $migraciones |
| Tablas de negocio (esquema público) | $tablas_vivas |
| Edge Functions | $functions |
| Buckets de Storage | $buckets |
| Pantallas Compose / ViewModels | $screens / $viewmodels |
| Líneas de código | Kotlin $(miles $loc_kt) · SQL $(miles $loc_sql) · TypeScript (funciones) $(miles $loc_ts_fn) · Astro $(miles $loc_astro) · TypeScript (admin) $(miles $loc_ts_admin) |
| Tests | $tests_jvm clases JVM · $tests_deno unitarios Deno · $tests_e2e scripts E2E |
| Versión actual de la app | $version |
| Páginas del sitio / vistas del admin | $paginas / $modulos_admin |
| Commits (app + sitio + admin) | $commits_total |
| Primer commit | $primero |
EOF
)
tabla_en=$(cat <<EOF
| Metric | Value |
|---|---|
| SQL migrations | $migraciones |
| Business tables (public schema) | $tablas_vivas |
| Edge Functions | $functions |
| Storage buckets | $buckets |
| Compose screens / ViewModels | $screens / $viewmodels |
| Lines of code | Kotlin $(miles $loc_kt) · SQL $(miles $loc_sql) · TypeScript (functions) $(miles $loc_ts_fn) · Astro $(miles $loc_astro) · TypeScript (admin) $(miles $loc_ts_admin) |
| Tests | $tests_jvm JVM classes · $tests_deno Deno unit · $tests_e2e E2E scripts |
| Current app version | $version |
| Site pages / admin views | $paginas / $modulos_admin |
| Commits (app + site + admin) | $commits_total |
| First commit | $primero |
EOF
)

echo "$tabla_es"
echo
echo "_Calculado el $fecha con scripts/metricas.sh_"

# --- escribir en los README entre marcadores --------------------------------
if [ "$escribir" = 1 ]; then
  reemplazar() { # archivo, tabla, texto de fecha
    local f="$1" t="$2" nota="$3" tmp
    tmp="$(mktemp)"
    awk -v tabla="$t" -v nota="$nota" '
      /<!-- metricas:inicio -->/ { print; print ""; print tabla; print ""; print nota; print ""; skip=1; next }
      /<!-- metricas:fin -->/ { skip=0 }
      !skip { print }
    ' "$f" > "$tmp" && mv "$tmp" "$f"
    echo "actualizado: $f"
  }
  reemplazar "$aqui/README.md" "$tabla_es" "_Calculado el $fecha con [\`scripts/metricas.sh\`](scripts/metricas.sh)._"
  [ -f "$aqui/README.en.md" ] && reemplazar "$aqui/README.en.md" "$tabla_en" "_Computed on $fecha with [\`scripts/metricas.sh\`](scripts/metricas.sh)._"
fi
