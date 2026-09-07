#!/usr/bin/env bash
set -u

# 360 CLI
BASE_URL="https://wiswfpfsjiowtrdyqpxy.supabase.co/functions/v1"
CSE_ID="e003eb0834b6b4be8"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BANNER="$ROOT_DIR/ui/banner.txt"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/360-cli"
CONFIG="$CONFIG_DIR/config"
mkdir -p "$CONFIG_DIR" 2>/dev/null || true

command -v curl >/dev/null 2>&1 || { echo "360 CLI requires curl." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "360 CLI requires python3." >&2; exit 1; }

# ---- Theme ----
COLOR_ENABLED="${COLOR_ENABLED:-1}"
ACCENT="${ACCENT:-cyan}"
[[ -f "$CONFIG" ]] && . "$CONFIG" 2>/dev/null || true

apply_theme(){
  if [[ "${COLOR_ENABLED:-1}" == "1" ]]; then
    RESET=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'
    case "${ACCENT:-cyan}" in
      blue) ACC=$'\033[38;5;75m';; green) ACC=$'\033[38;5;114m';;
      purple) ACC=$'\033[38;5;141m';; red) ACC=$'\033[38;5;203m';;
      yellow) ACC=$'\033[38;5;221m';; white) ACC=$'\033[97m';;
      *) ACC=$'\033[38;5;81m';;
    esac
    MUTED=$'\033[38;5;245m'; OK=$'\033[38;5;114m'; ERR=$'\033[38;5;203m'
  else
    RESET= BOLD= DIM= ACC= MUTED= OK= ERR=
  fi
}
apply_theme

clear_screen(){ printf '\033[2J\033[H'; }
pause(){ printf '\n%sPress Enter to return...%s ' "$MUTED" "$RESET"; IFS= read -r _ || true; }
is_back(){ [[ "${1:-}" == "b" || "${1:-}" == "B" ]]; }
read_input(){ IFS= read -r REPLY || true; [[ "$REPLY" == "b" || "$REPLY" == "B" ]]; }
confirm(){
  local prompt="${1:-Continue?}" answer
  printf '%s%s%s [Y/n] ' "$ACC" "$prompt" "$RESET"
  IFS= read -r answer || return 1
  case "${answer:-Y}" in y|Y|yes|YES) return 0;; *) return 1;; esac
}
back_prompt(){ printf '%s[Enter]%s Back   ' "$MUTED" "$RESET"; }

urlencode(){ python3 - "$1" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
PY
}

json_payload(){ python3 - "$@" <<'PY'
import json,sys
# args are key/value pairs
a=sys.argv[1:]
print(json.dumps(dict(zip(a[::2],a[1::2]))))
PY
}

open_web(){
  local url="$1"
  if command -v xdg-open >/dev/null 2>&1; then xdg-open "$url" >/dev/null 2>&1 &
  elif command -v open >/dev/null 2>&1; then open "$url" >/dev/null 2>&1 &
  elif command -v start >/dev/null 2>&1; then start "" "$url" >/dev/null 2>&1 &
  else
    printf '%sOpen: %s%s\n' "$ACC" "$url" "$RESET"
  fi
}

title(){
  clear_screen
  printf '%s%s%s\n' "$ACC" "$BOLD" "$1"
  printf '%s──────────────────────────────────────────────────%s\n' "$MUTED" "$RESET"
}

# ---- Search: the same Google Custom Search API used by the web search page ----
search(){
  title "360 Search"
  printf '%sSearch pill%s  › ' "$ACC" "$RESET"
  IFS= read -r q || true
  is_back "$q" && return
  [[ -z "${q// }" ]] && return
  printf '\n%sSearching…%s\n\n' "$DIM" "$RESET"
  local raw status eq
  eq="$(urlencode "$q")"
  raw="$(curl -sS --max-time 30 -o /tmp/360-search.$$ -w '%{http_code}' \
    "https://www.googleapis.com/customsearch/v1?key=AIzaSyD-9tSrke72PouQMnMX-a7eZSW0jkFMBWY&cx=${CSE_ID}&q=${eq}&num=10" 2>/dev/null)"
  status="$raw"; raw="$(cat /tmp/360-search.$$ 2>/dev/null)"; rm -f /tmp/360-search.$$
  if [[ "$status" != "200" ]]; then
    printf '%sSearch unavailable (HTTP %s).%s\n' "$ERR" "$status" "$RESET"
    printf '%s%s%s\n' "$MUTED" "${raw:0:240}" "$RESET"; pause; return
  fi
  python3 - "$raw" <<'PY'
import json,sys
d=json.loads(sys.argv[1]); items=d.get("items",[])
if not items: print("No results found."); raise SystemExit
for i,x in enumerate(items,1):
 print(f"{i:>2}. {x.get('title','Untitled')}")
 print(f"    {x.get('link','')}")
 print(f"    {(x.get('snippet') or '').replace(chr(10),' ')[:220]}")
 print()
PY
  pause
}

# ---- AI: real 360 AI streaming endpoint ----
ai(){
  local memory='[]'
  while true; do
    title "360 AI"
    printf '%sPrompt%s  › ' "$ACC" "$RESET"
    IFS= read -r prompt || return
    is_back "$prompt" && return
    [[ -z "${prompt// }" ]] && continue
    printf '\n%s360 AI is thinking…%s\n\n' "$DIM" "$RESET"
    local body tmp status answer
    body="$(python3 - "$prompt" "$memory" <<'PY'
import json,sys
print(json.dumps({"message":sys.argv[1],"memory":json.loads(sys.argv[2])}))
PY
)" || { printf '%sCould not build request.%s\n' "$ERR" "$RESET"; pause; continue; }
    tmp="$(mktemp)"
    status="$(curl -sS --max-time 180 -o "$tmp" -w '%{http_code}' -X POST "$BASE_URL/ai-chatbot" -H 'Content-Type: application/json' --data "$body" 2>/dev/null)"
    if [[ "$status" != "200" ]]; then
      printf '%sAI service unavailable (HTTP %s).%s\n' "$ERR" "$status" "$RESET"
      cat "$tmp" 2>/dev/null; rm -f "$tmp"; pause; continue
    fi
    answer="$(python3 - "$tmp" <<'PY'
import json,sys
out=[]
raw=open(sys.argv[1],encoding='utf8',errors='replace').read()
for line in raw.splitlines():
 if not line.startswith('data:'): continue
 try:
  e=json.loads(line[5:].strip())
 except Exception: continue
 if e.get('type')=='text':
  d=str(e.get('delta','')); out.append(d); print(d,end='',flush=True)
 elif e.get('type')=='error': print('\n\nError: '+str(e.get('message','AI request failed')))
print()
print(json.dumps(''.join(out)))
PY
)"
    # Last line is JSON-encoded assistant text.
    local encoded="${answer##*$'\n'}"
    if [[ "$encoded" != '""' && -n "$encoded" ]]; then
      memory="$(python3 - "$memory" "$prompt" "$encoded" <<'PY'
import json,sys
m=json.loads(sys.argv[1]); p=sys.argv[2]; a=json.loads(sys.argv[3])
m += [{"role":"user","content":p},{"role":"assistant","content":a}]
print(json.dumps(m[-20:]))
PY
)"
    fi
    rm -f "$tmp"
    printf '\n%sB%s Back   %sEnter%s New prompt\n' "$ACC" "$RESET" "$ACC" "$RESET"
    IFS= read -r next || return
    is_back "$next" && return
  done
}

# ---- Weather ----
weather(){
  title "360 Weather"
  printf '%sLocation%s  › ' "$ACC" "$RESET"
  IFS= read -r city || true
  is_back "$city" && return
  [[ -z "${city// }" ]] && return
  local geo data
  geo="$(curl -fsSL --max-time 15 -A '360-CLI/1.0' \
    "https://nominatim.openstreetmap.org/search?format=json&limit=1&q=$(urlencode "$city")" 2>/dev/null)" || {
      printf '%sLocation service unavailable.%s\n' "$ERR" "$RESET"; pause; return;
    }
  data="$(python3 - "$geo" <<'PY'
import json,sys
try:
 x=json.loads(sys.argv[1])
 if not x: raise SystemExit(1)
 print(x[0]["lat"]); print(x[0]["lon"]); print(x[0].get("display_name",""))
except: raise SystemExit(1)
PY
)" || { printf '%sLocation not found.%s\n' "$ERR" "$RESET"; pause; return; }
  mapfile -t loc <<<"$data"
  local lat="${loc[0]}" lon="${loc[1]}" name="${loc[2]}"
  local w
  w="$(curl -fsSL --max-time 20 \
    "https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,precipitation&daily=temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max,sunrise,sunset&forecast_days=5&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=auto" 2>/dev/null)" || {
      printf '%sWeather service unavailable.%s\n' "$ERR" "$RESET"; pause; return;
    }
  python3 - "$w" "$name" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); c=x["current"]; d=x["daily"]
desc={0:"Clear",1:"Mostly clear",2:"Partly cloudy",3:"Overcast",45:"Fog",48:"Fog",51:"Drizzle",53:"Drizzle",55:"Drizzle",61:"Rain",63:"Rain",65:"Heavy rain",71:"Snow",73:"Snow",75:"Heavy snow",80:"Showers",81:"Showers",82:"Heavy showers",95:"Thunderstorm",96:"Thunderstorm",99:"Thunderstorm"}
print(sys.argv[2]); print()
print(f"  {desc.get(c['weather_code'],'Unknown')}   {c['temperature_2m']:.0f}°F  (feels {c['apparent_temperature']:.0f}°F)")
print(f"  Humidity {c['relative_humidity_2m']}%   Wind {c['wind_speed_10m']:.0f} mph   Precip {c['precipitation']} in")
print()
for i,day in enumerate(d["time"]):
 print(f"  {day}   {d['temperature_2m_min'][i]:.0f}° / {d['temperature_2m_max'][i]:.0f}°   {desc.get(d['weather_code'][i],'Unknown')}   rain {d['precipitation_probability_max'][i]}%")
PY
  pause
}

# ---- News ----
news(){
  title "360 News"
  printf '%sLatest stories%s\n\n' "$ACC" "$RESET"
  local feeds=(
    "https://feeds.bbci.co.uk/news/rss.xml"
    "https://feeds.bbci.co.uk/news/technology/rss.xml"
    "https://feeds.bbci.co.uk/news/business/rss.xml"
    "https://feeds.bbci.co.uk/news/world/rss.xml"
    "https://www.nasa.gov/rss/dyn/breaking_news.rss"
    "https://www.wired.com/feed/rss"
  )
  local tmp; tmp="$(mktemp)"
  for f in "${feeds[@]}"; do
    curl -fsSL --max-time 8 "$f" 2>/dev/null | python3 -c '
import sys,xml.etree.ElementTree as ET
try:
 r=ET.fromstring(sys.stdin.read()); ch=r.find("channel")
 if ch is not None:
  for x in ch.findall("item")[:5]:
   t=(x.findtext("title") or "").strip(); u=(x.findtext("link") or "").strip()
   if t: print(t+"\t"+u)
except: pass
' >>"$tmp"
  done
  python3 - "$tmp" <<'PY'
import sys
rows=[]; seen=set()
for line in open(sys.argv[1],errors="ignore"):
 t,u=(line.rstrip("\n").split("\t",1)+[""])[:2]
 if t and t not in seen: rows.append((t,u)); seen.add(t)
for i,(t,u) in enumerate(rows[:24],1):
 print(f"{i:>2}. {t}\n    {u}\n")
if not rows: print("No news is available right now.")
PY
  rm -f "$tmp"; pause
}

# ---- Stocks ----
stocks(){
  title "360 Stocks"
  printf '%sTicker%s  › ' "$ACC" "$RESET"; IFS= read -r sym || true
  is_back "$sym" && return; [[ -z "${sym// }" ]] && return
  sym="${sym^^}"
  local r; r="$(curl -fsSL --max-time 20 "$BASE_URL/stock-data?symbol=$(urlencode "$sym")&range=1d" 2>/dev/null)" || { printf '%sStock service unavailable.%s\n' "$ERR" "$RESET"; pause; return; }
  python3 - "$r" "$sym" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); d=x.get('quote',x)
get=lambda *k: next((d.get(a) for a in k if isinstance(d,dict) and d.get(a) is not None),None)
company=get('companyName','longName','shortName') or sys.argv[2]
price=get('lastClose','regularMarketPrice','price','currentPrice')
chg=get('changePct','regularMarketChangePercent','changePercent')
print(f"{company}  ·  {sys.argv[2]}")
print()
print(f"  Price       {price if price is not None else '—'} {d.get('currency','') if isinstance(d,dict) else ''}".rstrip())
print(f"  Change      {chg:+.2f}%" if isinstance(chg,(int,float)) else "  Change      —")
for label,keys in [('Day range',('dayLow','regularMarketDayLow','low')),('52-week',('fiftyTwoWeekLow','52WeekLow')) ,('Volume',('volume','regularMarketVolume')),('Market cap',('marketCap',))]:
 v=get(*keys)
 if v is not None: print(f"  {label:<12}{v}")
PY
  pause
}

# ---- Translator: same MyMemory endpoint used by 360 ----
translate(){
  title "360 Translator"
  printf '%sText%s  › ' "$ACC" "$RESET"; IFS= read -r text || true
  is_back "$text" && return; [[ -z "${text// }" ]] && return
  printf '%sFrom [auto]%s › ' "$ACC" "$RESET"; IFS= read -r from || true; is_back "$from" && return; from="${from:-autodetect}"
  printf '%sTo%s         › ' "$ACC" "$RESET"; IFS= read -r to || true; is_back "$to" && return; to="${to:-es}"
  local r; r="$(curl -fsSL --max-time 30 "https://api.mymemory.translated.net/get?q=$(urlencode "$text")&langpair=$(urlencode "$from")|$(urlencode "$to")" 2>/dev/null)" || { printf '%sTranslation service unavailable.%s\n' "$ERR" "$RESET"; pause; return; }
  python3 - "$r" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); print(x.get('responseData',{}).get('translatedText') or x.get('responseDetails') or 'Translation failed.')
PY
  pause
}

# ---- URL shortener ----
shorten(){
  title "360 URL Shortener"
  printf '%sURL%s  › ' "$ACC" "$RESET"
  IFS= read -r url || true
  [[ -z "${url// }" ]] && return
  local body r
  body="$(python3 - "$url" <<'PY'
import json,sys
print(json.dumps({"url":sys.argv[1]}))
PY
)"
  r="$(curl -fsSL --max-time 30 -X POST "$BASE_URL/smooth-endpoint" -H 'Content-Type: application/json' --data "$body" 2>/dev/null)" || {
    printf '%sShortener unavailable.%s\n' "$ERR" "$RESET"; pause; return;
  }
  python3 - "$r" <<'PY'
import json,sys
x=json.loads(sys.argv[1])
print(x.get("shortUrl") or x.get("url") or x.get("short_url") or x.get("error") or json.dumps(x,indent=2))
PY
  pause
}

settings(){
  while true; do
    title "360 Settings"
    printf '  %s1%s  Colors: %s%s%s\n' "$ACC" "$RESET" "$BOLD" "$([[ "$COLOR_ENABLED" == "1" ]] && echo On || echo Off)" "$RESET"
    printf '  %s2%s  Accent: %s%s%s\n' "$ACC" "$RESET" "$BOLD" "$ACCENT" "$RESET"
    printf '  %s3%s  Back\n\n' "$ACC" "$RESET"
    printf '%s360 settings ›%s ' "$ACC" "$RESET"; IFS= read -r c || return
    is_back "$c" && return
    case "$c" in
      1) [[ "$COLOR_ENABLED" == "1" ]] && COLOR_ENABLED=0 || COLOR_ENABLED=1;;
      2)
        printf '\n  blue  green  purple  red  yellow  white  cyan\n\nAccent › '; IFS= read -r a || true
        is_back "$a" && continue
        case "$a" in blue|green|purple|red|yellow|white|cyan) ACCENT="$a";; *) continue;; esac
        ;;
      3) return;;
      *) continue;;
    esac
    printf 'COLOR_ENABLED=%q\nACCENT=%q\n' "$COLOR_ENABLED" "$ACCENT" >"$CONFIG"
    apply_theme
  done
}

menu(){
  clear_screen
  [[ -f "$BANNER" ]] && cat "$BANNER"
  printf '\n'
  printf '  %s1%s  Search\n' "$ACC" "$RESET"
  printf '  %s2%s  AI\n' "$ACC" "$RESET"
  printf '  %s3%s  Weather\n' "$ACC" "$RESET"
  printf '  %s4%s  News\n' "$ACC" "$RESET"
  printf '  %s5%s  Stocks\n' "$ACC" "$RESET"
  printf '  %s6%s  Translator\n' "$ACC" "$RESET"
  printf '  %s7%s  URL Shortener\n' "$ACC" "$RESET"
  printf '  %s8%s  Chat\n' "$ACC" "$RESET"
  printf '  %s9%s  Games\n' "$ACC" "$RESET"
  printf ' %s10%s  Apps\n' "$ACC" "$RESET"
  printf ' %s11%s  Settings\n' "$ACC" "$RESET"
  printf '\n  %sq%s  Quit\n\n' "$ACC" "$RESET"
  printf '%s360 ›%s ' "$ACC" "$RESET"
}

while true; do
  menu
  IFS= read -r choice || exit 0
  case "$choice" in
    1) search;;
    2) ai;;
    3) weather;;
    4) news;;
    5) stocks;;
    6) translate;;
    7) shorten;;
    8) open_web 'https://360-search.com/chat.html';;
    9) open_web 'https://360-search.com/games.html';;
    10) open_web 'https://360-search.com/apps.html';;
    11) settings;;
    b|B) continue;;
    q|Q|0) if confirm "Quit 360 CLI?"; then clear_screen; exit 0; fi;;
  esac
done
