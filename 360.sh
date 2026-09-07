!/usr/bin/env bash
set -u

BASE_URL="https://wiswfpfsjiowtrdyqpxy.supabase.co/functions/v1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BANNER="$ROOT_DIR/ui/banner.txt"

command -v curl >/dev/null 2>&1 || { echo "360 CLI requires curl." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "360 CLI requires python3." >&2; exit 1; }

clear_screen(){ printf '\033[2J\033[H'; }
press_enter(){ printf '\nPress Enter to return... '; read -r _; }
open_web(){
  local url="$1"
  if command -v xdg-open >/dev/null 2>&1; then xdg-open "$url" >/dev/null 2>&1 &
  elif command -v open >/dev/null 2>&1; then open "$url" >/dev/null 2>&1 &
  elif command -v start >/dev/null 2>&1; then start "" "$url" >/dev/null 2>&1 &
  else echo "Open this URL: $url"; fi
}

json_value(){ python3 - "$1" "$2" <<'PY'
import json,sys
try:
 d=json.loads(sys.argv[1]); k=sys.argv[2]
 v=d
 for p in k.split('.'):
  if isinstance(v,dict): v=v.get(p)
  else: v=None
 print(v if v is not None else '')
except Exception: print('')
PY
}

search(){
 clear_screen; echo "360 Search"; echo "────────────────────────────────────────"; printf 'Search: '; read -r q
 [[ -z "$q" ]] && return
 echo; echo "Searching..."; echo
 local raw
 raw=$(curl -fsS --max-time 20 -X POST "$BASE_URL/search" -H 'Content-Type: application/json' --data "$(python3 -c 'import json,sys; print(json.dumps({"q":sys.argv[1]}))' "$q")") || { echo "Search service unavailable."; press_enter; return; }
 python3 - "$raw" <<'PY'
import json,sys
try:
 d=json.loads(sys.argv[1])
 items=d.get('results') or d.get('data') or d.get('web') or []
 if isinstance(items,dict): items=items.get('results',[])
 if not items: print(json.dumps(d,indent=2)); raise SystemExit
 for i,x in enumerate(items[:10],1):
  title=x.get('title') or x.get('name') or '(untitled)'; url=x.get('url') or x.get('link') or ''
  desc=x.get('description') or x.get('snippet') or ''
  print(f'{i}. {title}\n   {url}\n   {desc[:220]}\n')
except Exception as e: print(sys.argv[1])
PY
 press_enter
}

ai(){
 clear_screen; echo "360 AI"; echo "────────────────────────────────────────"; printf 'Prompt: '; read -r prompt
 [[ -z "$prompt" ]] && return
 echo; echo "AI is thinking..."; echo
 local body response
 body=$(python3 -c 'import json,sys; print(json.dumps({"message":sys.argv[1],"memory":[]}))' "$prompt")
 response=$(curl -fsS --max-time 120 -X POST "$BASE_URL/ai-chatbot" -H 'Content-Type: application/json' -d "$body") || { echo "AI service unavailable."; press_enter; return; }
 python3 - "$response" <<'PY'
import json,sys
try:
 d=json.loads(sys.argv[1]);
 print(d.get('reply') or d.get('response') or d.get('content') or d.get('text') or d.get('message') or json.dumps(d,indent=2))
except: print(sys.argv[1])
PY
 press_enter
}

weather(){
 clear_screen; echo "360 Weather"; echo "────────────────────────────────────────"; printf 'City: '; read -r city
 [[ -z "$city" ]] && return
 local geo data lat lon name
 geo=$(curl -fsS --max-time 15 "https://nominatim.openstreetmap.org/search?format=json&q=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$city")&limit=1" -A '360-CLI/1.0') || { echo "Location service unavailable."; press_enter; return; }
 read -r lat lon name < <(python3 - "$geo" <<'PY'
import json,sys
x=json.loads(sys.argv[1]);
print((x[0]['lat'],x[0]['lon'],x[0].get('display_name','')) if x else ('','',''))
PY
)
 [[ -z "$lat" ]] && { echo "Location not found."; press_enter; return; }
 data=$(curl -fsS --max-time 20 "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,surface_pressure,visibility,cloud_cover,dew_point_2m,precipitation&hourly=temperature_2m,weather_code,precipitation_probability&daily=temperature_2m_max,temperature_2m_min,weather_code,sunrise,sunset,uv_index_max,precipitation_sum,wind_speed_10m_max&forecast_days=7&wind_speed_unit=kmh&timezone=auto") || { echo "Weather service unavailable."; press_enter; return; }
 python3 - "$data" "$name" <<'PY'
import json,sys
w=json.loads(sys.argv[1]); c=w['current']; d=w['daily'];
icons={0:'Clear',1:'Mainly clear',2:'Partly cloudy',3:'Overcast',45:'Fog',48:'Rime fog',51:'Drizzle',53:'Drizzle',55:'Drizzle',61:'Rain',63:'Rain',65:'Heavy rain',71:'Snow',73:'Snow',75:'Heavy snow',80:'Rain showers',81:'Rain showers',82:'Heavy showers',95:'Thunderstorm',96:'Thunderstorm',99:'Thunderstorm'}
print(sys.argv[2]); print(f"{icons.get(c['weather_code'],'Unknown')}  {c['temperature_2m']}°C (feels {c['apparent_temperature']}°C)"); print(f"Humidity: {c['relative_humidity_2m']}%   Wind: {c['wind_speed_10m']} km/h   Precip: {c['precipitation']} mm")
print('\n7-day forecast:')
for i,date in enumerate(d['time']): print(f"{date}: {d['temperature_2m_min'][i]}° / {d['temperature_2m_max'][i]}°  {icons.get(d['weather_code'][i],'Unknown')}  rain {d['precipitation_sum'][i]} mm")
PY
 press_enter
}

news(){
 clear_screen; echo "360 News"; echo "────────────────────────────────────────"; echo "Fetching current feeds..."; echo
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
 local tmp; tmp=$(mktemp); trap 'rm -f "$tmp"' RETURN
 for f in "${feeds[@]}"; do curl -fsSL --max-time 8 "$f" 2>/dev/null | python3 -c 'import sys,xml.etree.ElementTree as ET; from email.utils import parsedate_to_datetime
try:
 r=ET.fromstring(sys.stdin.read()); ch=r.find("channel");
 if ch is not None:
  for x in ch.findall("item")[:6]: print((x.findtext("title") or "").strip()+"\t"+(x.findtext("link") or ""))
except: pass' >> "$tmp"; done
 python3 - "$tmp" <<'PY'
import sys
rows=[]
for line in open(sys.argv[1],errors='ignore'):
 t,u=line.rstrip('\n').split('\t',1) if '\t' in line else (line.strip(),'')
 if t and (t,u) not in rows: rows.append((t,u))
for i,(t,u) in enumerate(rows[:30],1): print(f'{i}. {t}\n   {u}\n')
PY
 press_enter
}

stocks(){
 clear_screen; echo "360 Stocks"; echo "────────────────────────────────────────"; printf 'Ticker/company: '; read -r q
 [[ -z "$q" ]] && return
 local r; r=$(curl -fsS --max-time 20 "$BASE_URL/stock-data?action=search&q=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$q")") || { echo "Stock service unavailable."; press_enter; return; }
 python3 - "$r" <<'PY'
import json,sys
x=json.loads(sys.argv[1]);
for i,q in enumerate(x.get('quotes',[])[:10],1): print(f"{i}. {q.get('symbol','')} — {q.get('shortname') or q.get('longname') or ''}")
PY
 printf '\nSymbol for quote (Enter to cancel): '; read -r sym
 [[ -z "$sym" ]] && return
 r=$(curl -fsS --max-time 20 "$BASE_URL/stock-data?symbol=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$sym")&range=1d") || { echo "Quote unavailable."; press_enter; return; }
 python3 - "$r" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); print(json.dumps(x,indent=2))
PY
 press_enter
}

translate(){
 clear_screen; echo "360 Translator"; echo "────────────────────────────────────────"; printf 'Text: '; read -r text
 [[ -z "$text" ]] && return
 printf 'From [Auto-Detect]: '; read -r from; from=${from:-Auto-Detect}
 printf 'To [Spanish]: '; read -r to; to=${to:-Spanish}
 local body r; body=$(python3 -c 'import json,sys;print(json.dumps({"text":sys.argv[1],"from":sys.argv[2],"to":sys.argv[3]}))' "$text" "$from" "$to")
 r=$(curl -fsS --max-time 30 -X POST "$BASE_URL/dynamic-endpoint" -H 'Content-Type: application/json' -d "$body") || { echo "Translation service unavailable."; press_enter; return; }
 echo; python3 - "$r" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); print(x.get('translated') or json.dumps(x,indent=2))
PY
 press_enter
}

shorten(){
 clear_screen; echo "360 URL Shortener"; echo "────────────────────────────────────────"; printf 'URL: '; read -r url
 [[ -z "$url" ]] && return
 local body r; body=$(python3 -c 'import json,sys;print(json.dumps({"url":sys.argv[1]}))' "$url")
 r=$(curl -fsS --max-time 30 -X POST "$BASE_URL/smooth-endpoint" -H 'Content-Type: application/json' -d "$body") || { echo "Shortener unavailable."; press_enter; return; }
 echo; python3 - "$r" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); print(x.get('shortUrl') or x.get('error') or json.dumps(x,indent=2))
PY
 press_enter
}

menu(){
 clear_screen
 [[ -f "$BANNER" ]] && cat "$BANNER"
 cat <<'MENU'

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

  q  Quit
MENU
 printf '360 > '
}

while true; do
 menu; read -r choice
 case "$choice" in
  1) search;; 2) ai;; 3) weather;; 4) news;; 5) stocks;; 6) translate;; 7) shorten;;
  8) open_web 'https://360-search.com/chat.html';;
  9) open_web 'https://360-search.com/games.html';;
 10) open_web 'https://360-search.com/apps.html';;
  q|Q|0) clear_screen; exit 0;;
 esac
done
