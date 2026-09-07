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

if [[ "$COLOR_ENABLED" == "1" ]]; then
  RESET=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'
  case "$ACCENT" in
    blue) ACC=$'\033[38;5;75m';;
    green) ACC=$'\033[38;5;114m';;
    purple) ACC=$'\033[38;5;141m';;
    red) ACC=$'\033[38;5;203m';;
    yellow) ACC=$'\033[38;5;221m';;
    white) ACC=$'\033[97m';;
    *) ACC=$'\033[38;5;81m';;
  esac
  MUTED=$'\033[38;5;245m'; OK=$'\033[38;5;114m'; ERR=$'\033[38;5;203m'
else
  RESET= BOLD= DIM= ACC= MUTED= OK= ERR=
fi

clear_screen(){ printf '\033[2J\033[H'; }
pause(){ printf '\n%sPress Enter to return...%s ' "$MUTED" "$RESET"; IFS= read -r _ || true; }
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

# ---- Search: Google CSE element endpoint used by the normal search page ----
search(){
  title "360 Search"
  printf '%sSearch pill%s  › ' "$ACC" "$RESET"
  IFS= read -r q || true
  [[ -z "${q// }" ]] && return

  printf '\n%sSearching…%s\n\n' "$DIM" "$RESET"
  local eq raw
  eq="$(urlencode "$q")"
  # The CSE element endpoint returns the same structured result data used by
  # the Custom Search Element. JSONP is requested so no API key is required.
  raw="$(curl -fsSL --max-time 25 \
    -H 'Accept: application/javascript, application/json' \
    "https://cse.google.com/cse/element/v1?rsz=filtered_cse&num=10&hl=en&source=gcsc&q=${eq}&cx=${CSE_ID}&callback=_360cse" 2>/dev/null)" || {
      printf '%sSearch service unavailable.%s\n' "$ERR" "$RESET"; pause; return;
  }

  python3 - "$raw" <<'PY'
import json,re,sys
s=sys.argv[1].strip()
m=re.search(r'_360cse\((.*)\)\s*;?\s*$',s,re.S)
if m: s=m.group(1)
try:
    d=json.loads(s)
except Exception:
    print("No readable search results.")
    raise SystemExit
items=d.get("results",[])
if not items:
    print("No results found.")
    raise SystemExit
for i,x in enumerate(items,1):
    title=x.get("titleNoFormatting") or x.get("title") or "Untitled"
    url=x.get("formattedUrl") or x.get("url") or ""
    if isinstance(url,dict): url=url.get("url","")
    snippet=x.get("content") or x.get("snippet") or ""
    print(f"{i:>2}. {title}")
    print(f"    {url}")
    if snippet: print(f"    {snippet[:240]}")
    print()
PY
  pause
}

# ---- AI: matches assets/js/ai.js exactly: message + memory, SSE response ----
ai(){
  local memory='[]'
  while true; do
    title "360 AI"
    printf '%sPrompt%s  › ' "$ACC" "$RESET"
    IFS= read -r prompt || return
    [[ -z "${prompt// }" ]] && return

    printf '\n%s360 AI is thinking…%s\n\n' "$DIM" "$RESET"

    local body tmp status
    body="$(python3 - "$prompt" "$memory" <<'PY'
import json,sys
print(json.dumps({"message":sys.argv[1],"memory":json.loads(sys.argv[2])}))
PY
)" || { printf '%sCould not build request.%s\n' "$ERR" "$RESET"; pause; continue; }

    tmp="$(mktemp)"
    status="$(curl -sS --max-time 180 -o "$tmp" -w '%{http_code}' \
      -X POST "$BASE_URL/ai-chatbot" \
      -H 'Content-Type: application/json' \
      --data "$body")"
    if [[ "$status" != "200" ]]; then
      printf '%sAI service unavailable (HTTP %s).%s\n' "$ERR" "$status" "$RESET"
      cat "$tmp" 2>/dev/null
      rm -f "$tmp"; pause; continue
    fi

    python3 - "$tmp" <<'PY'
import json,sys
p=sys.argv[1]
buf=""
saw=False
try:
    with open(p,encoding="utf8",errors="replace") as f:
        for raw in f:
            line=raw.strip()
            if not line.startswith("data:"): continue
            payload=line[5:].strip()
            if not payload: continue
            try: e=json.loads(payload)
            except Exception: continue
            typ=e.get("type")
            if typ=="text":
                print(e.get("delta",""),end="",flush=True); saw=True
            elif typ=="error":
                print("\n\nError: "+str(e.get("message","AI request failed")),end="")
            elif typ=="done":
                print()
except Exception as ex:
    print("\nAI response could not be read: "+str(ex))
if not saw:
    try:
        d=json.loads(open(p,encoding="utf8",errors="replace").read())
        msg=d.get("reply") or d.get("error") or d.get("message")
        if msg: print(msg)
    except Exception: pass
PY
    # Keep conversation memory in the same plain role/content format as ai.js.
    local answer
    answer="$(python3 - "$tmp" <<'PY'
import json,sys
out=""
try:
    for raw in open(sys.argv[1],encoding="utf8",errors="replace"):
        if raw.startswith("data:"):
            try:
                e=json.loads(raw[5:].strip())
                if e.get("type")=="text": out+=str(e.get("delta",""))
            except: pass
except: pass
print(json.dumps(out))
PY
)"
    if [[ "$answer" != '""' ]]; then
      memory="$(python3 - "$memory" "$prompt" "$answer" <<'PY'
import json,sys
m=json.loads(sys.argv[1]); p=sys.argv[2]; a=json.loads(sys.argv[3])
m += [{"role":"user","content":p},{"role":"assistant","content":a}]
# Bound local context while preserving recent conversation.
print(json.dumps(m[-20:]))
PY
)"
    fi
    rm -f "$tmp"
    printf '\n%s' "$MUTED"; back_prompt; printf '%s' "$RESET"
    IFS= read -r _ || true
  done
}

# ---- Weather ----
weather(){
  title "360 Weather"
  printf '%sLocation%s  › ' "$ACC" "$RESET"
  IFS= read -r city || true
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
  printf '%sTicker%s  › ' "$ACC" "$RESET"
  IFS= read -r sym || true
  [[ -z "${sym// }" ]] && return
  sym="${sym^^}"
  local r
  r="$(curl -fsSL --max-time 20 \
    "$BASE_URL/stock-data?symbol=$(urlencode "$sym")&range=1d" 2>/dev/null)" || {
      printf '%sStock service unavailable.%s\n' "$ERR" "$RESET"; pause; return;
    }
  python3 - "$r" "$sym" <<'PY'
import json,sys
x=json.loads(sys.argv[1])
print(sys.argv[2]); print()
# Accommodate the common quote shapes returned by the function.
q=x.get("quote",x)
def g(*ks):
 for k in ks:
  if isinstance(q,dict) and q.get(k) is not None:return q[k]
 return None
for label,ks in [
 ("Price",("regularMarketPrice","price","currentPrice")),
 ("Change",("regularMarketChange","change","priceChange")),
 ("Change %",("regularMarketChangePercent","changePercent","percentChange")),
 ("Open",("regularMarketOpen","open")),
 ("High",("regularMarketDayHigh","dayHigh","high")),
 ("Low",("regularMarketDayLow","dayLow","low")),
 ("Volume",("regularMarketVolume","volume")),
]:
 v=g(*ks)
 if v is not None: print(f"  {label:<10} {v}")
if not any(g(*ks) is not None for _,ks in [("Price",("regularMarketPrice","price","currentPrice")),("Change",("regularMarketChange","change","priceChange"))]):
 print(json.dumps(x,indent=2))
PY
  pause
}

# ---- Translator: use the AI backend rather than a nonexistent dynamic endpoint ----
translate(){
  title "360 Translator"
  printf '%sText%s  › ' "$ACC" "$RESET"
  IFS= read -r text || true
  [[ -z "${text// }" ]] && return
  printf '%sFrom [auto]%s › ' "$ACC" "$RESET"; IFS= read -r from || true; from="${from:-auto}"
  printf '%sTo%s         › ' "$ACC" "$RESET"; IFS= read -r to || true; to="${to:-Spanish}"
  local prompt body tmp status
  prompt="Translate the following text from ${from} to ${to}. Return only the translation, with no explanation.

${text}"
  body="$(python3 - "$prompt" <<'PY'
import json,sys
print(json.dumps({"message":sys.argv[1],"memory":[]}))
PY
)"
  tmp="$(mktemp)"
  status="$(curl -sS --max-time 120 -o "$tmp" -w '%{http_code}' -X POST "$BASE_URL/ai-chatbot" -H 'Content-Type: application/json' --data "$body")"
  printf '\n'
  if [[ "$status" != "200" ]]; then
    printf '%sTranslation service unavailable (HTTP %s).%s\n' "$ERR" "$status" "$RESET"
    cat "$tmp"; rm -f "$tmp"; pause; return
  fi
  python3 - "$tmp" <<'PY'
import json,sys
for line in open(sys.argv[1],encoding="utf8",errors="replace"):
 if line.startswith("data:"):
  try:
   e=json.loads(line[5:].strip())
   if e.get("type")=="text": print(e.get("delta",""),end="",flush=True)
  except: pass
print()
PY
  rm -f "$tmp"; pause
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
    printf '%s360 settings ›%s ' "$ACC" "$RESET"
    IFS= read -r c || return
    case "$c" in
      1)
        [[ "$COLOR_ENABLED" == "1" ]] && COLOR_ENABLED=0 || COLOR_ENABLED=1
        printf 'COLOR_ENABLED=%q\nACCENT=%q\n' "$COLOR_ENABLED" "$ACCENT" >"$CONFIG"
        # reload this process' theme
        exec "$0"
        ;;
      2)
        printf '\n  blue  green  purple  red  yellow  white  cyan\n\n'
        printf 'Accent › '; IFS= read -r a || true
        case "$a" in blue|green|purple|red|yellow|white|cyan) ACCENT="$a";;
          *) continue;; esac
        printf 'COLOR_ENABLED=%q\nACCENT=%q\n' "$COLOR_ENABLED" "$ACCENT" >"$CONFIG"
        exec "$0"
        ;;
      3|"") return;;
    esac
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
    q|Q|0) clear_screen; exit 0;;
  esac
done
