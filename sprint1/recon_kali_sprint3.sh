#!/usr/bin/env bash
# recon_kali_sprint3.sh - Versión corregida y robusta (Sprint1)
# Autor: TU_NOMBRE (edita la variable AUTHOR si quieres)
AUTHOR="${AUTHOR:-TU_NOMBRE}"
TARGET_HOST="${TARGET_HOST:-frontendgit-09482557-4f090.web.app}"
DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
EVIDENCE_DIR="${EVIDENCE_DIR:-/root/evidence/sprint1}"

set -euo pipefail

mkdir -p "$EVIDENCE_DIR"

echo "author: $AUTHOR" > "$EVIDENCE_DIR/metadata.txt"
echo "target: $TARGET_HOST" >> "$EVIDENCE_DIR/metadata.txt"
echo "date_UTC: $DATE" >> "$EVIDENCE_DIR/metadata.txt"

log() {
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*"
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" >> "$EVIDENCE_DIR/execution_log_${DATE}.md"
}

check_tool() {
  if command -v "$1" >/dev/null 2>&1; then
    echo "ok"
  else
    echo "missing"
  fi
}

log "INICIO del recon para $TARGET_HOST. Autor: $AUTHOR"

# 1) Recon pasivo: crt.sh
log "1) Consulta crt.sh (certificados públicos)"
CRT_FILE="$EVIDENCE_DIR/crtsh_${DATE}.json"
curl -s "https://crt.sh/?q=%25${TARGET_HOST}&output=json" -o "$CRT_FILE" || echo "{}" > "$CRT_FILE"
if command -v jq >/dev/null 2>&1; then
  jq -r '.[].name_value' "$CRT_FILE" 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr ' ' '\n' | sort -u > "$EVIDENCE_DIR/subdomains_from_crtsh.txt" || true
else
  echo "jq no instalado: subdominios no extraídos automáticamente." >> "$EVIDENCE_DIR/execution_log_${DATE}.md"
fi
log "crt.sh guardado en $CRT_FILE"

# 2) whatweb (tecnologías)
if [ "$(check_tool whatweb)" = "ok" ]; then
  log "2) Ejecutando whatweb"
  whatweb "https://${TARGET_HOST}" -v > "$EVIDENCE_DIR/whatweb_${DATE}.txt" 2>&1 || true
  log "whatweb -> $EVIDENCE_DIR/whatweb_${DATE}.txt"
else
  log "whatweb no instalado: saltando"
fi

# 3) Resolución DNS (dig)
if [ "$(check_tool dig)" = "ok" ]; then
  log "3) Resolución DNS (dig)"
  dig +short A "$TARGET_HOST" > "$EVIDENCE_DIR/ips_${DATE}.txt" 2>/dev/null || true
  dig +short CNAME "$TARGET_HOST" > "$EVIDENCE_DIR/cname_${DATE}.txt" 2>/dev/null || true
  TARGET_IP="$(head -n1 "$EVIDENCE_DIR/ips_${DATE}.txt" || true)"
  if [ -n "${TARGET_IP:-}" ]; then
    echo "resolved_ip: $TARGET_IP" >> "$EVIDENCE_DIR/metadata.txt"
  fi
  log "IPs guardadas en $EVIDENCE_DIR/ips_${DATE}.txt (primera IP: ${TARGET_IP:-none})"
else
  log "dig no instalado: saltando resolución DNS"
fi

# 4) nmap - host discovery (conservador)
if [ "$(check_tool nmap)" = "ok" ]; then
  log "4) nmap host discovery (conservador)"
  if [ -n "${TARGET_IP:-}" ]; then
    nmap -sn -Pn -T2 -oN "$EVIDENCE_DIR/nmap_ping_scan_${DATE}.txt" "$TARGET_IP" || true
  else
    nmap -sn -Pn -T2 -oN "$EVIDENCE_DIR/nmap_ping_scan_${DATE}.txt" "$TARGET_HOST" || true
  fi
  log "nmap ping scan -> $EVIDENCE_DIR/nmap_ping_scan_${DATE}.txt"
else
  log "nmap no instalado: saltando scans"
fi

# 5) nmap - escaneo de puertos (TOP 1000, bajo)
if [ "$(check_tool nmap)" = "ok" ]; then
  log "5) nmap top-ports 1000 con detección de versiones (no agresivo). Solo si autorizado."
  if [ -n "${TARGET_IP:-}" ]; then
    nmap -sS -sV --top-ports 1000 -T2 -oN "$EVIDENCE_DIR/nmap_top1000_${DATE}.txt" -oX "$EVIDENCE_DIR/nmap_top1000_${DATE}.xml" "$TARGET_IP" || true
  else
    nmap -sS -sV --top-ports 1000 -T2 -oN "$EVIDENCE_DIR/nmap_top1000_${DATE}.txt" -oX "$EVIDENCE_DIR/nmap_top1000_${DATE}.xml" "$TARGET_HOST" || true
  fi
  log "nmap top1000 -> $EVIDENCE_DIR/nmap_top1000_${DATE}.txt"
fi

# 6) gobuster - enumeración de directorios (wordlist común)
if [ "$(check_tool gobuster)" = "ok" ]; then
  WB="/usr/share/wordlists/dirb/common.txt"
  if [ -f "$WB" ]; then
    log "6) gobuster dir con wordlist común (conservador)"
    gobuster dir -u "https://${TARGET_HOST}" -w "$WB" -t 10 -o "$EVIDENCE_DIR/gobuster_dirs_${DATE}.txt" 2>/dev/null || true
    log "gobuster -> $EVIDENCE_DIR/gobuster_dirs_${DATE}.txt"
  else
    log "wordlist $WB no encontrada; gobuster saltado"
  fi
else
  log "gobuster no instalado: saltando enumeración de directorios"
fi

# 7) amass/subfinder (opcionales)
if [ "$(check_tool amass)" = "ok" ]; then
  log "7) amass enum (opcional)"
  amass enum -d "${TARGET_HOST#*.}" -o "$EVIDENCE_DIR/subdomains_amass.txt" || true
  log "amass -> $EVIDENCE_DIR/subdomains_amass.txt"
else
  log "amass no instalado: skipping"
fi

if [ "$(check_tool subfinder)" = "ok" ]; then
  log "7b) subfinder (opcional)"
  subfinder -d "${TARGET_HOST#*.}" -o "$EVIDENCE_DIR/subdomains_subfinder.txt" || true
  log "subfinder -> $EVIDENCE_DIR/subdomains_subfinder.txt"
else
  log "subfinder no instalado: skipping"
fi

# 8) Guardar homepage, robots y sitemap
log "8) Guardando homepage, robots.txt y sitemap.xml si existen"
curl -s -D "$EVIDENCE_DIR/headers_${DATE}.txt" "https://${TARGET_HOST}" -o "$EVIDENCE_DIR/homepage_${DATE}.html" || true
curl -s "https://${TARGET_HOST}/robots.txt" -o "$EVIDENCE_DIR/robots_${DATE}.txt" || echo "no-robots" > "$EVIDENCE_DIR/robots_${DATE}.txt"
curl -s "https://${TARGET_HOST}/sitemap.xml" -o "$EVIDENCE_DIR/sitemap_${DATE}.xml" || echo "no-sitemap" > "$EVIDENCE_DIR/sitemap_${DATE}.xml"
log "Archivos guardados: headers, homepage, robots, sitemap"

# 9) nmap vuln scripts (solo detección - ligero)
if [ "$(check_tool nmap)" = "ok" ]; then
  log "9) nmap --script vuln (ligero, detección)"
  if [ -n "${TARGET_IP:-}" ]; then
    nmap -sV --script vuln -T2 -oN "$EVIDENCE_DIR/nmap_vuln_${DATE}.txt" "$TARGET_IP" || true
  else
    nmap -sV --script vuln -T2 -oN "$EVIDENCE_DIR/nmap_vuln_${DATE}.txt" "$TARGET_HOST" || true
  fi
  log "nmap vuln -> $EVIDENCE_DIR/nmap_vuln_${DATE}.txt"
fi

# 10) Inventario simple CSV
INV="$EVIDENCE_DIR/asset_inventory_${DATE}.csv"
echo "tipo,activo,fuente,verificado_por,fecha_verificacion" > "$INV"
echo "dominio,${TARGET_HOST},user_input,${AUTHOR},${DATE}" >> "$INV"
if [ -n "${TARGET_IP:-}" ]; then
  echo "ip,${TARGET_IP},dig,${AUTHOR},${DATE}" >> "$INV"
fi
log "Inventario generado -> $INV"

log "FIN del recon. Revisa la carpeta: $EVIDENCE_DIR"
log "Resumen: metadata, crtsh, whatweb (si disponible), nmap outputs, gobuster (si ejecutado), execution log."
exit 0
