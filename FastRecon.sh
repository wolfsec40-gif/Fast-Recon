#!/usr/bin/env bash
#
# FastRecon.sh
# -----------------------------------------------------
# Parallelized subdomain & endpoint reconnaissance pipeline
#
# Usage:
#   ./FastRecon.sh targets.txt /path/to/wordlist.txt
#
# Prerequisites:
#   subfinder, assetfinder, amass, bbot, ffuf, subdog,
#   sudomy, dnscan, subdominator, webcopilot,
#   httpx, anew, jq, nmap, wfuzz, dirb, gobuster, dirsearch,
#   curl, prips
#
# Notes:
#   - Provide your own API keys via environment variables
#     e.g. export GITHUB_TOKEN="xxxxx"
#     e.g. export SECURITYTRAILS_KEY="xxxxx"
#
# -----------------------------------------------------

set -euo pipefail

TARGETS_FILE="${1:-targets.txt}"
WORDLIST="${2:-/path/to/wordlist.txt}"
OUTDIR="recon_results_$(date +%F_%H-%M)"
mkdir -p "$OUTDIR"

log() { echo -e "\n[+] $*\n"; }

# -----------------------------------------------------
# 1. Parallel Basic Subdomain Enumeration
# -----------------------------------------------------
log "Starting parallel subdomain enumeration"

(
  subfinder -dL "$TARGETS_FILE" -all -recursive -o "$OUTDIR/subfinder.txt" &
  
  while read -r domain; do
      assetfinder --subs-only "$domain"
  done < "$TARGETS_FILE" > "$OUTDIR/assetfinder.txt" &
  
  amass enum -passive -df "$TARGETS_FILE" -o "$OUTDIR/amass.txt" &
  
  bbot -l "$TARGETS_FILE" -p subdomain-enum cloud-enum code-enum email-enum spider \
       web-basic paramminer dirbust-light web-screenshots --allow-deadly \
       -o "$OUTDIR/bbot.json" &
  
  cat "$TARGETS_FILE" | subdog -tools all > "$OUTDIR/subdog.txt" &
  
  sudomy -dL "$TARGETS_FILE" --all -o "$OUTDIR/sudomy.txt" &
  
  dnscan -l "$TARGETS_FILE" -w "$WORDLIST" -r --maxdepth 3 -o "$OUTDIR/dnscan.txt" &
  
  subdominator -dL "$TARGETS_FILE" -o "$OUTDIR/subdominator.txt" &
  
  sudo webcopilot -f "$TARGETS_FILE" -a -t 500 -o "$OUTDIR/webcopilot.txt" &
  
  wait
)

# -----------------------------------------------------
# 2. Parallel Extra Sources
# -----------------------------------------------------
log "Collecting from extra sources (crt.sh, GitHub, Shrewdeye, SecurityTrails)"

> "$OUTDIR/crtsh.txt"
> "$OUTDIR/github_subs.txt"
> "$OUTDIR/shrewdeye.txt"
> "$OUTDIR/securitytrails.txt"

while read -r domain; do
    (
      curl -s "https://crt.sh/?q=%25.${domain}" |
        grep -oP '(?<=>)[a-z0-9.-]+\.'"${domain}"'(?=<)' |
        sort -u >> "$OUTDIR/crtsh.txt" &
      
      [[ -n "${GITHUB_TOKEN:-}" ]] && \
        github-subdomains -d "$domain" -t "$GITHUB_TOKEN" -o - >> "$OUTDIR/github_subs.txt" &
      
      curl -s "https://shrewdeye.app/api/v1/domains/${domain}/resources" |
        jq -r '.data[].name' | sort -u >> "$OUTDIR/shrewdeye.txt" &
      
      [[ -n "${SECURITYTRAILS_KEY:-}" ]] && \
        curl -s "https://api.securitytrails.com/v1/domain/${domain}/subdomains" \
          -H "APIKEY: ${SECURITYTRAILS_KEY}" |
          jq -r '.subdomains[]' | sed "s/$/.${domain}/" | sort -u >> "$OUTDIR/securitytrails.txt" &
      
      wait
    )
done < "$TARGETS_FILE"

# -----------------------------------------------------
# 3. ASN & CIDR Enumeration
# -----------------------------------------------------
log "Running ASN and CIDR reconnaissance"

ASN_FILE="$OUTDIR/asns.txt"
CIDR_FILE="$OUTDIR/cidrs.txt"
> "$ASN_FILE"; > "$CIDR_FILE"

while read -r domain; do
    amass intel -org "$domain" -o "$OUTDIR/amass_asn_${domain}.txt" || true
    cat "$OUTDIR/amass_asn_${domain}.txt" >> "$ASN_FILE"
done < "$TARGETS_FILE"

sort -u "$ASN_FILE" -o "$ASN_FILE"

while read -r asn; do
    whois -h whois.radb.net -- "-i origin: ${asn}" |
        grep -Eo "([0-9.]+){4}/[0-9]+" | sort -u >> "$CIDR_FILE"
done < "$ASN_FILE"

# Reverse DNS sweep on CIDRs
while read -r cidr; do
    for ip in $(prips "$cidr"); do
        dig -x "$ip" +short
    done
done < "$CIDR_FILE" > "$OUTDIR/prips_rdns.txt"

# -----------------------------------------------------
# 4. Combine & De-duplicate
# -----------------------------------------------------
log "Combining and deduplicating all subdomains"

cat "$OUTDIR"/*.txt | anew > "$OUTDIR/all_subs.txt"
log "Total unique subdomains: $(wc -l < "$OUTDIR/all_subs.txt")"

# -----------------------------------------------------
# 5. Probing & Port Scanning
# -----------------------------------------------------
log "Probing live hosts"
cat "$OUTDIR/all_subs.txt" | httpx -silent -o "$OUTDIR/httpx_alive.txt"

log "Running nmap full port scan"
nmap -iL "$OUTDIR/all_subs.txt" -p- --open -T4 \
     -oG "$OUTDIR/nmap_grep.txt" \
     -oN "$OUTDIR/nmap.txt"

# -----------------------------------------------------
# 6. Endpoint Discovery on Live Hosts
# -----------------------------------------------------
log "Discovering endpoints on live hosts"
mkdir -p "$OUTDIR/endpoints"

while read -r url; do
    wfuzz -c -w "$WORDLIST" -u "$url/FUZZ" --hc 404 \
        | tee "$OUTDIR/endpoints/wfuzz_$(echo $url | sed 's~https\?://~~; s~[^a-zA-Z0-9]~_~g').txt"
done < "$OUTDIR/httpx_alive.txt"

while read -r url; do
    dirb "$url" "$WORDLIST" \
        -o "$OUTDIR/endpoints/dirb_$(echo $url | sed 's~https\?://~~; s~[^a-zA-Z0-9]~_~g').txt"
done < "$OUTDIR/httpx_alive.txt"

while read -r url; do
    gobuster dir -u "$url" -w "$WORDLIST" --wildcard \
        -o "$OUTDIR/endpoints/gobuster_$(echo $url | sed 's~https\?://~~; s~[^a-zA-Z0-9]~_~g').txt"
done < "$OUTDIR/httpx_alive.txt"

first=$(head -n1 "$OUTDIR/httpx_alive.txt")
[ -n "$first" ] && dirsearch -u "$first" -m POST GET PATCH DELETE \
                 -o "$OUTDIR/endpoints/dirsearch_first.txt"

# -----------------------------------------------------
# 7. Targeted Port Fuzzing (based on nmap results)
# -----------------------------------------------------
log "Starting targeted port fuzzing"
mkdir -p "$OUTDIR/port_fuzz"

grep "/open/" "$OUTDIR/nmap_grep.txt" | while read -r line; do
    domain=$(echo "$line" | awk '{print $2}')
    ports=$(echo "$line" | grep -oE '[0-9]+/open' | cut -d/ -f1)
    for port in $ports; do
        ffuf -u "https://$domain:$port/FUZZ" \
             -w "$WORDLIST" \
             -mc 200,301,302,403 \
             -o "$OUTDIR/port_fuzz/${domain}_${port}.json" || true
    done
done

log "Recon completed successfully. All results saved in: $OUTDIR"
