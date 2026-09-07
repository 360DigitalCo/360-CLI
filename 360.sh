#!/usr/bin/env bash
set -u

# 360 CLI — terminal interface for the real 360 services.
# No voice-search/web-only feature is emulated here.

BASE_URL="https://wiswfpfsjiowtrdyqpxy.supabase.co/functions/v1"
SUPABASE_URL="https://wiswfpfsjiowtrdyqpxy.supabase.co"
SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJvbGUiOiJhbm9uIiwiaWF0IjoxNzY4MzM4ODk3LCJleHAiOjIwODM5MTQ4OTl9.z_4FtM2c8UwgrRlafPYjolQuod4IoHQats95XHio1zM"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BANNER="$ROOT_DIR/ui/banner.txt"

CURL="$(command -v curl || true)"
PYTHON="$(command -v python3 || true)"

[[ -n "$CURL" ]] || { echo "360 CLI requires curl." >&2; exit 1; }
[[ -n "$PYTHON" ]] || { echo "360 CLI requires python3." >&2; exit 1; }

# ANSI colors are configurable in Settings.
COLOR_ENABLED=1
ACCENT='36'
DIM='2'

c() {
  local code="$1"; shift
  if [[ "$COLOR_ENABLED" == 1 ]]; then printf '\033[%sm%s\033[0m' "$code" "$*"; else printf '%s' "$*"; fi
}

clear_screen() { printf '\033[2J\033[H'; }
back_prompt() { printf '\n  '; c "${ACCENT}" 'b'; printf ' Back  '; c "${DIM}" 'Enter'; printf ' to return'; printf '\n'; }
press_enter() { printf '\n  Press Enter to return... '; read -r _; }


urlencode() {
  "$PYTHON" - "$1" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
PY
}

json() {
  "$PYTHON" - "$@" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
print(json.dumps(obj, separators=(',', ':')))
PY
}

open_web() {
  local url="$1"
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 &
  elif command -v open >/dev/null 2>&1; then
    open "$url" >/dev/null 2>&1 &
  elif command -v start >/dev/null 2>&1; then
    start "" "$url" >/dev/null 2>&1 &
  else
    printf '\n%s\n' "$url"
  fi
}

fn_curl() {
  # The 360 website sends both of these headers to its Supabase functions.
  "$CURL" -fsSL --max-time "${MAX_TIME:-30}" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
    "$@"
}

post_fn() {
  local endpoint="$1" body="$2"
  fn_curl -X POST "$BASE_URL/$endpoint" \
    -H 'Content-Type: application/json' \
    --data "$body"
}

print_banner() {
  [[ -f "$BANNER" ]] && cat "$BANNER"
}

search() {
  clear_screen
  print_banner
  printf '\n  360 Search\n  ────────────────────────────────────────\n\n'
  printf '  Search  › '
  read -r q
  [[ -z "$q" ]] && return

  local body raw
  body=$("$PYTHON" -c 'import json,sys; print(json.dumps({"q":sys.argv[1],"tab":"web","safe":"moderate"}))' "$q")

  printf '\n  Searching…\n\n'
  MAX_TIME=30 raw=$(post_fn search "$body") || {
    echo '  Search service unavailable.'
    press_enter
    return
  }

  "$PYTHON" - "$raw" <<'PY'
import json, sys
try:
    d = json.loads(sys.argv[1])
    if d.get("error"):
        print("  Error: " + str(d["error"]))
        raise SystemExit

    items = d.get("web") or d.get("results") or d.get("data") or []
    if isinstance(items, dict):
        items = items.get("results") or items.get("web") or []

    if not items:
        print("  No results found.")
        raise SystemExit

    for i, item in enumerate(items[:10], 1):
        title = item.get("title") or item.get("name") or "Untitled"
        url = item.get("url") or item.get("link") or ""
        desc = item.get("description") or item.get("snippet") or ""
        print(f"  {i}. {title}")
        if url:
            print(f"     {url}")
        if desc:
            print(f"     {str(desc).replace(chr(10),' ')[:220]}")
        print()
except Exception:
    print(sys.argv[1])
PY

  press_enter
}

ai() {
  clear_screen
  print_banner
  printf '\n  360 AI\n  ────────────────────────────────────────\n\n'
  printf '  Prompt  › '
  read -r prompt
  [[ -z "$prompt" ]] && return

  local body
  body=$("$PYTHON" -c 'import json,sys; print(json.dumps({"messages":[{"role":"user","content":sys.argv[1]}],"stream":True}))' "$prompt")

  printf '\n  360 AI is thinking…\n\n'
  local raw status
  raw=$(MAX_TIME=120 post_fn ai-proxy "$body" 2>/dev/null) || {
    printf '  AI service unavailable.\n'
    press_enter
    return
  }

  # ai-proxy streams Server-Sent Events. Render text deltas and ignore
  # internal thinking deltas so the terminal shows the actual answer.
  "$PYTHON" - "$raw" <<'PY'
import sys, json
raw=sys.argv[1]
answer=[]
model=None
for line in raw.splitlines():
    line=line.strip()
    if not line or line.startswith(':'):
        continue
    if line.startswith('data:'):
        payload=line[5:].strip()
        if payload == '[DONE]':
            continue
        try:
            d=json.loads(payload)
        except Exception:
            continue
        typ=d.get('type')
        if typ == 'text':
            delta=d.get('delta','')
            print(delta, end='', flush=True)
            answer.append(delta)
        elif typ == 'done':
            model=d.get('model')
        elif 'choices' in d:
            for ch in d.get('choices',[]):
                delta=(ch.get('delta') or {}).get('content') or ''
                if delta:
                    print(delta, end='', flush=True)
                    answer.append(delta)
    elif line.startswith('{'):
        try:
            d=json.loads(line)
            if d.get('error'):
                print('\n  Error: '+str(d['error']))
        except Exception:
            pass

print()
PY
  press_enter
}

weather() {
  clear_screen
  print_banner
  printf '\n  360 Weather\n  ────────────────────────────────────────\n\n'
  printf '  City  › '
  read -r city
  [[ -z "$city" ]] && return

  local geo data lat lon display
  geo=$("$CURL" -fsSL --max-time 15 \
    "https://nominatim.openstreetmap.org/search?format=json&q=$(urlencode "$city")&limit=1" \
    -A '360-CLI/1.0') || {
      echo '  Location service unavailable.'
      press_enter
      return
    }

  read -r lat lon display < <("$PYTHON" - "$geo" <<'PY'
import json,sys
x=json.loads(sys.argv[1])
if not x:
    print("  ","","",sep="")
else:
    print(x[0].get("lat",""), x[0].get("lon",""), x[0].get("display_name",""))
PY
)

  [[ -n "$lat" && -n "$lon" ]] || {
    echo '  Location not found.'
    press_enter
    return
  }

  data=$("$CURL" -fsSL --max-time 20 \
    "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,surface_pressure,visibility,cloud_cover,dew_point_2m,precipitation&hourly=temperature_2m,weather_code,precipitation_probability&daily=temperature_2m_max,temperature_2m_min,weather_code,sunrise,sunset,uv_index_max,precipitation_sum,wind_speed_10m_max&forecast_days=7&wind_speed_unit=kmh&timezone=auto") || {
      echo '  Weather service unavailable.'
      press_enter
      return
    }

  "$PYTHON" - "$data" "$display" <<'PY'
import json,sys
w=json.loads(sys.argv[1]); c=w["current"]; d=w["daily"]
desc={0:"Clear sky",1:"Mainly clear",2:"Partly cloudy",3:"Overcast",45:"Foggy",48:"Icy fog",51:"Light drizzle",53:"Drizzle",55:"Heavy drizzle",61:"Light rain",63:"Rain",65:"Heavy rain",71:"Light snow",73:"Snowfall",75:"Heavy snow",77:"Snow grains",80:"Rain showers",81:"Heavy showers",82:"Violent showers",85:"Snow showers",86:"Heavy snow showers",95:"Thunderstorm",96:"Thunderstorm with hail",99:"Thunderstorm with heavy hail"}
dirs=["N","NE","E","SE","S","SW","W","NW"]
wind_dir=dirs[round(float(c.get("wind_direction_10m",0))/45)%8]
print("  " + sys.argv[2].split(",")[0:2][0] + (", " + sys.argv[2].split(",")[1].strip() if "," in sys.argv[2] else ""))
print(f"  {desc.get(c['weather_code'],'Unknown')}  {c['temperature_2m']}°C  (feels {c['apparent_temperature']}°C)")
print(f"  Humidity {c['relative_humidity_2m']}%  ·  Wind {c['wind_speed_10m']} km/h {wind_dir}  ·  Precip {c['precipitation']} mm")
print(f"  Pressure {c['surface_pressure']} hPa  ·  Visibility {c['visibility']/1000:.1f} km  ·  Cloud {c['cloud_cover']}%")
print("\n  7-day forecast")
for i,date in enumerate(d["time"]):
    print(f"  {date}: {d['temperature_2m_min'][i]}° / {d['temperature_2m_max'][i]}°  {desc.get(d['weather_code'][i],'Unknown')}  · rain {d['precipitation_sum'][i]} mm")
PY
  press_enter
}

news() {
  clear_screen
  print_banner
  printf '\n  360 News\n  ────────────────────────────────────────\n\n'
  echo '  Fetching current feeds…'

  local feeds=(
    'https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml'
    'https://feeds.bbci.co.uk/news/rss.xml'
    'https://techcrunch.com/feed/'
    'https://feeds.bbci.co.uk/news/technology/rss.xml'
    'https://www.nasa.gov/rss/dyn/breaking_news.rss'
    'https://feeds.bbci.co.uk/news/science_and_environment/rss.xml'
    'https://rss.nytimes.com/services/xml/rss/nyt/Business.xml'
    'https://feeds.bbci.co.uk/news/business/rss.xml'
    'https://rss.nytimes.com/services/xml/rss/nyt/World.xml'
    'https://feeds.bbci.co.uk/news/world/rss.xml'
    'https://www.wired.com/feed/rss'
    'https://www.theverge.com/rss/index.xml'
  )

  local tmp f
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' RETURN

  for f in "${feeds[@]}"; do
    "$CURL" -fsSL --max-time 8 "$f" 2>/dev/null | \
      "$PYTHON" -c '
import sys,xml.etree.ElementTree as ET
try:
    root=ET.fromstring(sys.stdin.read())
    channel=root.find("channel")
    if channel is not None:
        for x in channel.findall("item")[:6]:
            t=(x.findtext("title") or "").strip()
            u=(x.findtext("link") or "").strip()
            if t: print(t.replace("\t"," ")+"\t"+u)
except Exception: pass
' >> "$tmp"
  done

  "$PYTHON" - "$tmp" <<'PY'
import sys
rows=[]
for line in open(sys.argv[1],encoding="utf-8",errors="ignore"):
    t,u=(line.rstrip("\n").split("\t",1)+[""])[:2]
    if t and (t,u) not in rows: rows.append((t,u))
for i,(t,u) in enumerate(rows[:30],1):
    print(f"  {i}. {t}")
    if u: print(f"     {u}")
    print()
if not rows: print("  No news articles could be loaded right now.")
PY

  press_enter
}

stocks() {
  clear_screen
  print_banner
  printf '\n  360 Stocks\n  ────────────────────────────────────────\n\n'
  printf '  Ticker / company  › '
  read -r q
  [[ -z "$q" ]] && return

  local r sym range
  r=$(fn_curl --max-time 20 "$BASE_URL/stock-data?action=search&q=$(urlencode "$q")") || {
    echo '  Stock service unavailable.'
    press_enter
    return
  }

  "$PYTHON" - "$r" <<'PY'
import json,sys
x=json.loads(sys.argv[1])
quotes=x.get("quotes",[])
if not quotes:
    print("  No matches.")
else:
    for i,q in enumerate(quotes[:10],1):
        print(f"  {i}. {q.get('symbol','')} — {q.get('name') or q.get('shortname') or q.get('longname') or ''} {('· '+q.get('exchange','')) if q.get('exchange') else ''}")
PY

  printf '\n  Symbol  › '
  read -r sym
  [[ -z "$sym" ]] && return
  sym="${sym^^}"

  printf '  Range [6mo] › '
  read -r range
  range=${range:-6mo}

  r=$(fn_curl --max-time 30 "$BASE_URL/stock-data?symbol=$(urlencode "$sym")&range=$(urlencode "$range")") || {
    echo '  Quote unavailable.'
    press_enter
    return
  }

  "$PYTHON" - "$r" "$range" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); rng=sys.argv[2]
if x.get("error"):
    print("  Error: " + str(x["error"]))
    raise SystemExit
print(f"  {x.get('companyName','—')} · {x.get('exchangeName','')}")
print(f"  {x.get('symbol','—')}   {x.get('lastClose','—')} {x.get('currency','')}")
if x.get('changePct') is not None: print(f"  Today: {x['changePct']:+.2f}%")
for label,key in [("Day range","dayLow"),("52-week low","fiftyTwoWeekLow"),("52-week high","fiftyTwoWeekHigh"),("Market cap","marketCap"),("Volume","volume"),("Avg volume","avgVolume"),("P/E","peRatio"),("Forward P/E","forwardPE"),("Beta","beta"),("Sector","sector"),("Industry","industry")]:
    if x.get(key) is not None: print(f"  {label}: {x[key]}")
tech=x.get("technical") or {}
if tech.get("outlookLabel"): print(f"  Outlook: {tech['outlookLabel']}")
if tech.get("signals"):
    print("  Signals:")
    for s in tech["signals"]: print(f"    • {s}")
PY
  press_enter
}

translate() {
  clear_screen
  print_banner
  printf '\n  360 Translator\n  ────────────────────────────────────────\n\n'
  printf '  Text  › '
  read -r text
  [[ -z "$text" ]] && return
  printf '  From [Auto-Detect]  › '
  read -r from
  from=${from:-Auto-Detect}
  printf '  To [Spanish]  › '
  read -r to
  to=${to:-Spanish}

  local body r
  body=$("$PYTHON" -c 'import json,sys; print(json.dumps({"text":sys.argv[1],"from":sys.argv[2],"to":sys.argv[3]}))' "$text" "$from" "$to")
  r=$(post_fn dynamic-endpoint "$body") || {
    echo '  Translation service unavailable.'
    press_enter
    return
  }

  "$PYTHON" - "$r" <<'PY'
import json,sys
x=json.loads(sys.argv[1])
if x.get("error"): print("  Error: " + str(x["error"]))
elif x.get("translated"): print("\n  " + str(x["translated"]))
else: print("  No translation returned.")
PY
  press_enter
}

shorten() {
  clear_screen
  print_banner
  printf '\n  360 URL Shortener\n  ────────────────────────────────────────\n\n'
  printf '  URL  › '
  read -r url
  [[ -z "$url" ]] && return

  local body r
  body=$("$PYTHON" -c 'import json,sys; print(json.dumps({"url":sys.argv[1]}))' "$url")
  r=$(post_fn smooth-endpoint "$body") || {
    echo '  URL shortener unavailable.'
    press_enter
    return
  }

  "$PYTHON" - "$r" <<'PY'
import json,sys
x=json.loads(sys.argv[1])
if x.get("shortUrl"): print("\n  Short URL: " + str(x["shortUrl"]))
elif x.get("error"): print("  Error: " + str(x["error"]))
else: print("  Failed to shorten URL.")
PY
  press_enter
}

settings() {
  while true; do
    clear_screen
    print_banner
    printf '\n  360 Settings\n  ────────────────────────────────────────\n\n'
    printf '  1  Colors: '; [[ "$COLOR_ENABLED" == 1 ]] && echo 'On' || echo 'Off'
    printf '  2  Accent: %s\n' "$ACCENT"
    printf '  3  Back\n\n  360 settings › '
    read -r setting
    case "$setting" in
      1) if [[ "$COLOR_ENABLED" == 1 ]]; then COLOR_ENABLED=0; else COLOR_ENABLED=1; fi ;;
      2)
        printf '\n  Accent color:\n'
        printf '  1 Cyan   2 Blue   3 Green   4 Magenta   5 Yellow   6 White\n  › '
        read -r a
        case "$a" in 1) ACCENT=36;;2) ACCENT=34;;3) ACCENT=32;;4) ACCENT=35;;5) ACCENT=33;;6) ACCENT=37;; esac
        ;;
      3|b|B|q|Q|'') return ;;
    esac
  done
}

menu() {
  clear_screen
  print_banner
  cat <<'MENU'

  ┌──────────────────────────────────────────────────┐
  │  Search  ›                                      │
  └──────────────────────────────────────────────────┘

    1  Search
    2  AI
    3  Weather
    4  News
    5  Stocks
    6  Translator
    7  URL Shortener
    8  Chat
    9  Games
   10  Apps
   11  Settings

    q  Quit
MENU
  printf '  360 › '
}

while true; do
  menu
  read -r choice
  case "$choice" in
    1) search ;;
    2) ai ;;
    3) weather ;;
    4) news ;;
    5) stocks ;;
    6) translate ;;
    7) shorten ;;
    8) open_web 'https://360-search.com/chat.html' ;;
    9) open_web 'https://360-search.com/games.html' ;;
   10) open_web 'https://360-search.com/apps.html' ;;
   11) settings ;;
    q|Q|0) clear_screen; exit 0 ;;
  esac
done
