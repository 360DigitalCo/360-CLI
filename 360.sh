#!/usr/bin/env bash
set -u

BASE_URL="https://wiswfpfsjiowtrdyqpxy.supabase.co/functions/v1"
CSE_ID="e003eb0834b6b4be8"
SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Indpc3dmcGZzamlvd3RyZHlxcHh5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgzMzg4OTcsImV4cCI6MjA4MzkxNDg5N30.z_4FtM2c8UwgrRlafPYjolQuod4IoHQats95XHio1zM"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BANNER="$ROOT_DIR/ui/banner.txt"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/360-cli"
CONFIG="$CONFIG_DIR/config"
mkdir -p "$CONFIG_DIR" 2>/dev/null || true

command -v curl >/dev/null 2>&1 || { echo "360 CLI requires curl." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "360 CLI requires python3." >&2; exit 1; }

COLOR_ENABLED="1"
ACCENT="cyan"
LOADING_ENABLED="1"
LOADING_STYLE="loop"
OFFLINE_MODE="0"
[[ -f "$CONFIG" ]] && . "$CONFIG" 2>/dev/null || true
LOADER_PID=""
trap spinner_stop EXIT

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

clear_screen(){ if command -v clear >/dev/null 2>&1 && [[ -t 1 ]]; then clear; else printf '\033[2J\033[H'; fi; }
pause(){ printf '\n%sPress Enter to return...%s ' "$MUTED" "$RESET"; IFS= read -r _ || true; }
is_back(){ [[ "${1:-}" == "b" || "${1:-}" == "B" ]]; }
confirm(){
  local prompt="${1:-Continue?}" answer
  printf '%s%s%s [Y/n] ' "$ACC" "$prompt" "$RESET"
  IFS= read -r answer || return 1
  case "${answer:-Y}" in y|Y|yes|YES) return 0;; *) return 1;; esac
}
back_or_stay(){
  if is_back "${1:-}"; then
    confirm "Go back?" && return 0
    return 2
  fi
  return 1
}
urlencode(){ python3 - "$1" <<'PY'
import sys,urllib.parse
print(urllib.parse.quote(sys.argv[1],safe=''))
PY
}
copy_to_clipboard(){
  local text="$1"
  if command -v wl-copy >/dev/null 2>&1; then printf '%s' "$text" | wl-copy; return 0; fi
  if command -v xclip >/dev/null 2>&1; then printf '%s' "$text" | xclip -selection clipboard; return 0; fi
  if command -v xsel >/dev/null 2>&1; then printf '%s' "$text" | xsel --clipboard --input; return 0; fi
  return 1
}

network_online(){
  [[ "${OFFLINE_MODE:-0}" == "1" ]] && return 1
  curl -fsSI --connect-timeout 1 --max-time 2 https://www.google.com >/dev/null 2>&1
}

save_history(){
  local query="$1"
  [[ -z "${query// }" ]] && return 0
  mkdir -p "$CONFIG_DIR" 2>/dev/null || true
  touch "$CONFIG_DIR/history" 2>/dev/null || true
  printf '%s\n' "$query" >> "$CONFIG_DIR/history"
  tail -n 50 "$CONFIG_DIR/history" > "$CONFIG_DIR/history.tmp" 2>/dev/null && mv "$CONFIG_DIR/history.tmp" "$CONFIG_DIR/history" 2>/dev/null || true
}

show_history(){
  title "360 History"
  if [[ ! -s "$CONFIG_DIR/history" ]]; then
    printf '%sNo search history yet.%s\n' "$MUTED" "$RESET"
  else
    nl -ba "$CONFIG_DIR/history" | tail -n 20
  fi
  printf '\n%sB%s Back\n' "$ACC" "$RESET"
  IFS= read -r _ || true
}

show_help(){
  title "360 Help"
  cat <<'HELP'

  Interactive
    360                 Open the 360 CLI menu

  Commands
    360 search QUERY   Search the web
    360 ai PROMPT      Ask 360 AI
    360 weather CITY   Weather
    360 news           News
    360 stocks TICKER  Stock quote
    360 translate TEXT Translate text
    360 shorten URL    Shorten a URL
    360 history        Search history
    360 status         System + service status
    360 settings       CLI settings
    360 help           Show this help
    360 offline        Toggle offline mode

  Global keys
    B  Back
    Q  Quit
    C  Copy a selected URL when available
HELP
  printf '\n%sB%s Back\n' "$ACC" "$RESET"
  IFS= read -r _ || true
}

show_status(){
  title "360 Status"
  local os kernel arch shell terminal network
  os="$(. /etc/os-release 2>/dev/null; printf '%s %s' "${NAME:-Linux}" "${VERSION_ID:-}")"
  kernel="$(uname -r 2>/dev/null || printf 'unknown')"
  arch="$(uname -m 2>/dev/null || printf 'unknown')"
  shell="${SHELL##*/}"
  terminal="${TERM:-unknown}"
  if network_online; then network="Online"; else network="Offline"; fi
  printf '  OS          %s\n' "$os"
  printf '  Kernel      %s\n' "$kernel"
  printf '  Architecture %s\n' "$arch"
  printf '  Shell       %s\n' "$shell"
  printf '  Terminal    %s\n' "$terminal"
  printf '  Network     %s\n' "$network"
  printf '  360 mode    %s\n' "$([[ "$OFFLINE_MODE" == 1 ]] && printf 'Offline' || printf 'Online')"
  printf '  Curl        %s\n' "$(curl --version 2>/dev/null | head -n1 | sed 's/^curl //' || printf 'unknown')"
  printf '  Python      %s\n' "$(python3 --version 2>/dev/null | awk '{print $2}' || printf 'unknown')"
  printf '\n%sB%s Back\n' "$ACC" "$RESET"
  IFS= read -r _ || true
}

open_web(){
  local url="$1"
  if command -v xdg-open >/dev/null 2>&1; then xdg-open "$url" >/dev/null 2>&1 &
  elif command -v open >/dev/null 2>&1; then open "$url" >/dev/null 2>&1 &
  elif command -v start >/dev/null 2>&1; then start "" "$url" >/dev/null 2>&1 &
  else printf '%sOpen: %s%s\n' "$ACC" "$url" "$RESET"; fi
}
title(){ clear_screen; printf '%s%s%s\n' "$ACC" "$BOLD" "$1"; printf '%s──────────────────────────────────────────────────%s\n' "$MUTED" "$RESET"; }
loading_frames(){
  case "${LOADING_STYLE:-loop}" in
    dots) printf '%s\n' '.' 'o' 'O' 'o';;
    bar) printf '%s\n' '[    ]' '[=   ]' '[==  ]' '[=== ]' '[====]' '[ ===]' '[  ==]' '[   =]';;
    pulse) printf '%s\n' '·' '•' '●' '•';;
    *) printf '%s\n' '-' '/' '|' '\\';;
  esac
}
spinner_start(){
  [[ "${LOADING_ENABLED:-1}" == "1" ]] || return 0
  local tty=/dev/tty
  [[ -w "$tty" ]] || return 0
  local frames; frames="$(loading_frames)"
  (
    while true; do
      while IFS= read -r frame; do
        printf '\r%s%s%s' "$DIM" "$frame" "$RESET" >"$tty"
        sleep 0.12
      done <<< "$frames"
    done
  ) &
  LOADER_PID=$!
}
spinner_stop(){
  [[ -n "${LOADER_PID:-}" ]] || return 0
  kill "$LOADER_PID" 2>/dev/null || true
  wait "$LOADER_PID" 2>/dev/null || true
  LOADER_PID=""
  [[ -w /dev/tty ]] && printf '\r\033[K' >/dev/tty
}

# Google CSE is a browser widget, not the JSON API. When Chromium is installed,
# run the same 360 search page headlessly so no Google API key is required.

ai_search_once(){
  local prompt="$1" tmp body
  printf '%sConnecting to 360 AI…%s\n' "$DIM" "$RESET"
  body="$(python3 - "$prompt" <<'PY'
import json,sys
print(json.dumps({'message':sys.argv[1],'memory':[]}))
PY
)"
  tmp="$(mktemp)"
  if ! curl -sS -N --connect-timeout 12 --max-time 180 -X POST "$BASE_URL/ai-chatbot" \
      -H 'Content-Type: application/json' -d "$body" 2>/dev/null |
      python3 - <<'PY'
import sys,json
for line in sys.stdin:
    if not line.startswith('data:'): continue
    try:
        e=json.loads(line[5:].strip())
    except: continue
    if e.get('type')=='text':
        print(e.get('delta',''),end='',flush=True)
PY
  then
    printf '\n%sAI service unavailable.%s\n' "$ERR" "$RESET"
  fi
  printf '\n\n%sB%s Back\n' "$ACC" "$RESET"
  IFS= read -r b || true
  if is_back "$b"; then confirm "Go back?" || true; fi
  rm -f "$tmp"
}
cse_search(){
  title "360 Search"

  local q="${*:-}"
  if [[ -z "${q// }" ]]; then
    printf '%sSearch pill%s  › ' "$ACC" "$RESET"
    IFS= read -r q || true
  else
    printf '%sSearch pill%s  › %s\n' "$ACC" "$RESET" "$q"
  fi

  if is_back "$q"; then confirm "Go back?" && return; fi
  [[ -z "${q// }" ]] && return
  save_history "$q"

  if [[ "$OFFLINE_MODE" == "1" ]]; then
    title "360 Search · Offline"
    printf '%sOffline mode is enabled. Network search is disabled.%s\n' "$MUTED" "$RESET"
    printf '\n%sB%s Back\n' "$ACC" "$RESET"
    IFS= read -r _ || true
    return
  fi

  local mode="web" modepick
  while true; do
    clear_screen
    printf '%s%sSearch%s  › %s\n' "$ACC" "$BOLD" "$RESET" "$q"
    printf '  %sW%s Web   %sN%s News   %sA%s AI   %sB%s Back\n\n' \
      "$ACC" "$RESET" "$ACC" "$RESET" "$ACC" "$RESET" "$ACC" "$RESET"
    printf 'Mode › '
    IFS= read -r modepick || return
    case "${modepick:-W}" in
      w|W) mode="web"; break;;
      n|N) mode="news"; break;;
      a|A) mode="ai"; break;;
      b|B) confirm "Go back?" && return;;
      q|Q) confirm "Quit 360 CLI?" && { clear_screen; exit 0; };;
    esac
  done

  if [[ "$mode" == "ai" ]]; then
    ai_search_once "$q"
    return
  fi

  # Normalize only for provider requests. The displayed query stays untouched.
  local provider_q="${q,,}"

  local tmp cse_tmp ddg_tmp edge_tmp wiki_tmp
  tmp="$(mktemp)"
  cse_tmp="$(mktemp)"
  ddg_tmp="$(mktemp)"
  edge_tmp="$(mktemp)"
  wiki_tmp="$(mktemp)"

  cleanup_search(){
    rm -f "$tmp" "$cse_tmp" "$ddg_tmp" "$edge_tmp" "$wiki_tmp"
  }
  trap cleanup_search RETURN

  # Provider 1: Google CSE. Uses the same CX/API configuration as 360 Search.
  # Results are consumed as provider data; no browser widget is needed here.
  (
    curl -sS --compressed --connect-timeout 1 --max-time 5 \
      "https://www.google.com/search?cx=$CSE_ID&q=$(urlencode "$provider_q")&num=10&gbv=1" \
      -A '360-CLI/1.0' \
      >"$cse_tmp" 2>/dev/null || true
  ) & cse_pid=$!

  # Provider 2: DuckDuckGo fast HTML endpoint.
  (
    curl -sS --compressed --connect-timeout 1 --max-time 4 \
      "https://lite.duckduckgo.com/lite/?q=$(urlencode "$provider_q")" \
      -A 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36' \
      >"$ddg_tmp" 2>/dev/null || true
  ) & ddg_pid=$!

  # Provider 3: 360's own index, kept as another independent source.
  (
    curl -sS --compressed --connect-timeout 1 --max-time 5 -X POST "$BASE_URL/search" \
      -H 'Content-Type: application/json' \
      -H "apikey: $SUPABASE_ANON_KEY" \
      -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
      --data "$(python3 - "$provider_q" <<'PY'
import json,sys
print(json.dumps({'q':sys.argv[1],'tab':'web','safe':'moderate'}))
PY
)" >"$edge_tmp" 2>/dev/null || true
  ) & edge_pid=$!

  # Knowledge panel runs independently and NEVER blocks web-result display.
  (
    curl -sS --compressed --connect-timeout 1 --max-time 3 \
      "https://en.wikipedia.org/w/api.php?action=query&generator=search&gsrsearch=$(urlencode "$provider_q")&gsrnamespace=0&gsrlimit=1&prop=extracts|info&exintro=1&explaintext=1&inprop=url&format=json" \
      -A '360-CLI/1.0' >"$wiki_tmp" 2>/dev/null || true
  ) & wiki_pid=$!

  parse_cse(){
    python3 - "$cse_tmp" "$tmp" <<'PY'
from html.parser import HTMLParser
from html import unescape
from urllib.parse import urlparse, parse_qs
import sys
class P(HTMLParser):
 def __init__(self): super().__init__(); self.rows=[]; self.cur=None; self.h3=False
 def handle_starttag(self,t,a):
  d=dict(a); cls=d.get('class','')
  if t=='div' and 'MjjYud' in cls: self.cur={'t':'','u':'','d':''}
  elif self.cur and t=='a' and d.get('href') and not self.cur['u']: self.cur['u']=d['href']
  elif self.cur and t=='h3': self.h3=True
 def handle_endtag(self,t):
  if self.cur and t=='h3': self.h3=False
  if self.cur and t=='div' and self.cur['t'] and self.cur['u']:
   self.rows.append(self.cur); self.cur=None
 def handle_data(self,d):
  if not self.cur:return
  if self.h3:self.cur['t']+=d
  elif not self.cur['d'] and d.strip():self.cur['d']+=' '+d
try:
 p=P(); p.feed(open(sys.argv[1],encoding='utf-8',errors='ignore').read())
 seen=set(); n=0
 with open(sys.argv[2],'w',encoding='utf-8') as o:
  for x in p.rows:
   u=unescape(x['u']).strip(); t=' '.join(unescape(x['t']).split()); d=' '.join(unescape(x['d']).split())
   if u.startswith('/url?'): u=parse_qs(urlparse(u).query).get('q',[''])[0]
   if not u.startswith(('http://','https://')) or 'google.' in urlparse(u).netloc: continue
   k=u.rstrip('/').lower()
   if not t or k in seen: continue
   seen.add(k); n+=1; o.write(f'{n}\t{t}\t{u}\t{d[:300]}\n')
   if n>=10: break
except Exception:pass
PY
  }

  parse_ddg(){
    python3 - "$ddg_tmp" "$tmp" <<'PY'
from html.parser import HTMLParser
from html import unescape
import sys
class P(HTMLParser):
 def __init__(self): super().__init__(); self.items=[]; self.cur=None; self.field=None
 def handle_starttag(self,t,a):
  d=dict(a); c=d.get('class','')
  if t=='a' and 'result__a' in c: self.cur={'t':'','u':d.get('href',''),'d':''}; self.field='t'
  elif self.cur and 'result__snippet' in c: self.field='d'
 def handle_endtag(self,t):
  if not self.cur:return
  if t=='a' and self.field=='t': self.field=None
  elif t=='div' and self.field=='d': self.items.append(self.cur); self.cur=None; self.field=None
 def handle_data(self,d):
  if self.cur and self.field:self.cur[self.field]+=d
try:
 p=P(); p.feed(open(sys.argv[1],encoding='utf-8',errors='ignore').read())
 with open(sys.argv[2],'w',encoding='utf-8') as o:
  n=0
  for x in p.items:
   t=' '.join(unescape(x['t']).split());u=unescape(x['u']).strip();d=' '.join(unescape(x['d']).split())
   if u and t:
    n+=1;o.write(f'{n}\t{t}\t{u}\t{d[:300]}\n')
    if n>=10:break
except Exception:pass
PY
  }

  parse_edge(){
    python3 - "$edge_tmp" "$tmp" <<'PY'
import json,sys
try:
 x=json.load(open(sys.argv[1])); items=x.get('web') or x.get('results') or x.get('data') or []
 if isinstance(items,dict): items=items.get('results') or items.get('items') or []
 with open(sys.argv[2],'w') as o:
  n=0
  for r in items:
   if not isinstance(r,dict):continue
   u=str(r.get('url') or r.get('link') or '').strip()
   t=' '.join(str(r.get('title') or r.get('name') or 'Untitled').split())
   d=' '.join(str(r.get('snippet') or r.get('description') or '').split())
   if u:
    n+=1;o.write(f'{n}\t{t}\t{u}\t{d[:300]}\n')
except Exception:pass
PY
  }

  print_results(){
    python3 - "$tmp" <<'PY'
import sys
for line in open(sys.argv[1],encoding='utf-8',errors='ignore'):
 p=line.rstrip('\n').split('\t')
 if len(p)>=3:
  n,t,u,d=(p+[''])[:4]
  print(f'{n}. {t}')
  print(f'   \x1b]8;;{u}\x1b\\{u}\x1b]8;;\x1b\\')
  if d: print(f'   {d}')
  print()
PY
  }

  printf '%sSearching%s ' "$DIM" "$RESET"
  spinner_start

  local shown=0 started_at=$EPOCHREALTIME deadline=$((SECONDS+5))
  while (( SECONDS < deadline )); do
    if [[ $shown -eq 0 && -s "$cse_tmp" ]]; then
      parse_cse
      if [[ -s "$tmp" ]]; then
        spinner_stop
        clear_screen
        title "360 Search · Web"
        printf '%sQuery%s  %s\n\n' "$MUTED" "$RESET" "$q"
        shown=1
        break
      fi
    fi

    if [[ $shown -eq 0 && -s "$ddg_tmp" ]]; then
      parse_ddg
      if [[ -s "$tmp" ]]; then
        spinner_stop
        clear_screen
        title "360 Search · Web"
        printf '%sQuery%s  %s\n\n' "$MUTED" "$RESET" "$q"
        shown=1
        break
      fi
    fi

    if [[ $shown -eq 0 && -s "$edge_tmp" ]]; then
      parse_edge
      if [[ -s "$tmp" ]]; then
        spinner_stop
        clear_screen
        title "360 Search · Web"
        printf '%sQuery%s  %s\n\n' "$MUTED" "$RESET" "$q"
        shown=1
        break
      fi
    fi

    sleep 0.02
  done
  spinner_stop

  # Render a compact knowledge panel at the top-left, then print results beside/below it.
  local panel=""
  if [[ -s "$wiki_tmp" ]]; then
    panel="$(python3 - "$wiki_tmp" <<'PY'
import json,sys,textwrap
try:
 x=json.load(open(sys.argv[1])); pages=x.get('query',{}).get('pages') or {}
 for v in pages.values():
  title=v.get('title'); ex=' '.join((v.get('extract') or '').split()); url=v.get('fullurl') or ''
  if title and ex:
   print(title)
   for line in textwrap.wrap(ex[:420], width=34):
    print(line)
   if url: print(url)
   break
except Exception: pass
PY
)"
  fi

  local elapsed
  elapsed="$(awk -v s="$started_at" -v e="$EPOCHREALTIME" 'BEGIN { printf "%.2f", e-s }')"

  if [[ $shown -eq 0 ]]; then
    parse_cse
    [[ ! -s "$tmp" ]] && parse_ddg
    [[ ! -s "$tmp" ]] && parse_edge
    clear_screen
    title "360 Search · ${mode^}"
    printf '%sQuery%s  %s\n' "$MUTED" "$RESET" "$q"
    shown=1
  fi

  local result_count
  result_count="$(awk 'END {print NR+0}' "$tmp")"
  printf '%s%s results · %ss%s\n\n' "$ACC" "$result_count" "$elapsed" "$RESET"

  # The panel is printed first so it occupies the upper-left corner of the search view.
  if [[ -n "$panel" ]]; then
    printf '%s╭─ Knowledge ───────────────────────────╮%s\n' "$ACC" "$RESET"
    local panel_line
    while IFS= read -r panel_line; do
      printf '%s│%s %-39.39s %s│%s\n' "$ACC" "$RESET" "$panel_line" "$ACC" "$RESET"
    done <<< "$panel"
    printf '%s╰───────────────────────────────────────╯%s\n\n' "$ACC" "$RESET"
  fi

  if [[ -s "$tmp" ]]; then
    print_results
  else
    printf '%sNo results found.%s\n' "$ERR" "$RESET"
  fi

  printf '\n%sNumber%s Open   %sC%s Copy   %sN%s New search   %sB%s Back   %sQ%s Quit\n' \
    "$ACC" "$RESET" "$ACC" "$RESET" "$ACC" "$RESET" "$ACC" "$RESET" "$ACC" "$RESET"
  printf '%sSearch ›%s ' "$ACC" "$RESET"
  IFS= read -r pick || true

  case "$pick" in
    c|C)
      printf '%sResult number to copy › %s' "$ACC" "$RESET"
      IFS= read -r cpick || true
      copied="$(awk -F '\t' -v n="$cpick" '$1==n{print $3;exit}' "$tmp")"
      if [[ -n "$copied" ]] && copy_to_clipboard "$copied"; then
        printf '%sCopied.%s\n' "$OK" "$RESET"
      else
        printf '%sClipboard tool unavailable.%s\n' "$ERR" "$RESET"
      fi
      IFS= read -r _ || true
      ;;
    b|B) confirm "Go back?" && return;;
    n|N) cse_search;;
    q|Q) confirm "Quit 360 CLI?" && { clear_screen; exit 0; };;
    [0-9]*)
      chosen="$(awk -F '\t' -v n="$pick" '$1==n{print $3;exit}' "$tmp")"
      [[ -n "$chosen" ]] && open_web "$chosen"
      ;;
  esac

  trap - RETURN
  cleanup_search
}

ai(){
  local memory='[]'
  while true; do
    title "360 AI"
    printf '%sPrompt%s  › ' "$ACC" "$RESET"
    prompt="${ai_prefill:-}"
    if [[ -z "${prompt// }" ]]; then IFS= read -r prompt || return; fi
    if is_back "$prompt"; then confirm "Go back?" && return; continue; fi
    [[ -z "${prompt// }" ]] && continue
    printf '\n%sConnecting to 360 AI…%s\n' "$DIM" "$RESET"
    local body tmp
    body="$(python3 - "$prompt" "$memory" <<'PY'
import json,sys
print(json.dumps({'message':sys.argv[1],'memory':json.loads(sys.argv[2])}))
PY
)"
    tmp="$(mktemp)"
    python3 - "$BASE_URL/ai-chatbot" "$body" "$tmp" <<'PY'
import json,sys,subprocess,time
url,body,outfile=sys.argv[1:]
cmd=['curl','-sS','-N','--connect-timeout','15','--max-time','240','-X','POST',url,
     '-H','Content-Type: application/json','--data',body]
start=time.time(); answer=[]; saw=False; err=None
p=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
with open(outfile,'w',encoding='utf-8') as out:
  try:
    for line in p.stdout:
      line=line.rstrip('\n')
      if not line.startswith('data:'): continue
      try: e=json.loads(line[5:].strip())
      except: continue
      typ=e.get('type')
      if typ=='thinking':
        if not saw: print('\r\033[K'+f'360 AI is thinking… {time.time()-start:.1f}s',end='',flush=True)
      elif typ=='tool':
        print('\r\033[K'+f"Using {e.get('name') or 'tool'}…",end='',flush=True)
      elif typ=='text':
        saw=True; d=str(e.get('delta','')); answer.append(d); out.write(d); out.flush(); print(d,end='',flush=True)
      elif typ=='error': err=str(e.get('message','AI request failed'))
  finally:
    try: p.wait(timeout=5)
    except subprocess.TimeoutExpired: p.kill()
if not answer:
  if err: print('\n\nError: '+err)
  else: print('\n\nAI returned no text.')
else: print()
final=''.join(answer)
with open(outfile,'a',encoding='utf-8') as out: out.write('\n'+json.dumps(final))
PY
    local rc=$? response answer_text
    response="$(tail -n 1 "$tmp" 2>/dev/null || true)"
    if [[ $rc -ne 0 || -z "$response" || "$response" == '""' ]]; then
      printf '%sAI service unavailable.%s\n' "$ERR" "$RESET"
      rm -f "$tmp"; pause; continue
    fi
    answer_text="$(python3 - "$response" <<'PY'
import json,sys
try: print(json.loads(sys.argv[1]))
except: print('')
PY
)"
    memory="$(python3 - "$memory" "$prompt" "$answer_text" <<'PY'
import json,sys
m=json.loads(sys.argv[1]); m += [{'role':'user','content':sys.argv[2]},{'role':'assistant','content':sys.argv[3]}]
print(json.dumps(m[-20:]))
PY
)"
    rm -f "$tmp"
    printf '\n%sB%s Back   %sEnter%s New prompt\n' "$ACC" "$RESET" "$ACC" "$RESET"
    IFS= read -r next || return
    if is_back "$next"; then confirm "Go back?" && return; fi
  done
}

weather(){
  title "360 Weather"; printf '%sLocation%s  › ' "$ACC" "$RESET"; city="${weather_prefill:-}"; if [[ -z "${city// }" ]]; then IFS= read -r city || true; else printf "%s\n" "$city"; fi
  if is_back "$city"; then confirm "Go back?" && return; fi
  [[ -z "${city// }" ]] && return
  local geo; spinner_start; geo="$(curl -fsSL --max-time 15 -A '360-CLI/1.0' "https://nominatim.openstreetmap.org/search?format=json&limit=1&q=$(urlencode "$city")" 2>/dev/null)"; spinner_stop
  if [[ -z "$geo" ]]; then printf '%sLocation service unavailable.%s\n' "$ERR" "$RESET"; pause; return; fi
  mapfile -t loc < <(python3 - "$geo" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); print(x[0]['lat'],x[0]['lon'],x[0].get('display_name','')) if x else None
PY
)
  [[ ${#loc[@]} -eq 0 ]] && { printf '%sLocation not found.%s\n' "$ERR" "$RESET"; pause; return; }
  read -r lat lon name <<<"${loc[0]}"
  local w; spinner_start; w="$(curl -fsSL --max-time 20 "https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,precipitation&daily=temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max,sunrise,sunset&forecast_days=5&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=auto" 2>/dev/null)"; spinner_stop
  if [[ -z "$w" ]]; then printf '%sWeather service unavailable.%s\n' "$ERR" "$RESET"; pause; return; fi
  python3 - "$w" "$city" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); c=x['current']; d=x['daily']; desc={0:'Clear',1:'Mostly clear',2:'Partly cloudy',3:'Overcast',45:'Fog',48:'Fog',51:'Drizzle',53:'Drizzle',55:'Drizzle',61:'Rain',63:'Rain',65:'Heavy rain',71:'Snow',73:'Snow',75:'Heavy snow',80:'Showers',81:'Showers',82:'Heavy showers',95:'Thunderstorm',96:'Thunderstorm',99:'Thunderstorm'}
print(f"{sys.argv[2]}")
print(f"  {desc.get(c['weather_code'],'Unknown')}   {c['temperature_2m']:.0f}°F  (feels {c['apparent_temperature']:.0f}°F)")
print(f"  Humidity {c['relative_humidity_2m']}%   Wind {c['wind_speed_10m']:.0f} mph   Precip {c['precipitation']} mm")
print('\n  Forecast')
for i,day in enumerate(d['time']): print(f"  {day}  {d['temperature_2m_min'][i]:.0f}° / {d['temperature_2m_max'][i]:.0f}°  {desc.get(d['weather_code'][i],'Unknown')}  {d['precipitation_probability_max'][i]}% rain")
PY
  pause
}

news(){
  title "360 News"; printf '%sLatest stories%s\n\n' "$ACC" "$RESET"
  local feeds=("https://feeds.bbci.co.uk/news/rss.xml" "https://feeds.bbci.co.uk/news/technology/rss.xml" "https://feeds.bbci.co.uk/news/business/rss.xml" "https://feeds.bbci.co.uk/news/world/rss.xml" "https://www.nasa.gov/rss/dyn/breaking_news.rss" "https://www.wired.com/feed/rss")
  local tmp; tmp="$(mktemp)"
  spinner_start
  for f in "${feeds[@]}"; do curl -fsSL --max-time 8 "$f" 2>/dev/null | python3 -c 'import sys,xml.etree.ElementTree as ET
try:
 r=ET.fromstring(sys.stdin.read()); c=r.find("channel")
 if c is not None:
  for x in c.findall("item")[:5]:
   t=(x.findtext("title") or "").strip(); u=(x.findtext("link") or "").strip()
   if t: print(t+"\t"+u)
except: pass' >>"$tmp"; done
  spinner_stop
  python3 - "$tmp" <<'PY'
import sys
rows=[]; seen=set()
for l in open(sys.argv[1],errors='ignore'):
 t,u=(l.rstrip('\n').split('\t',1)+[''])[:2]
 if t and t not in seen: rows.append((t,u)); seen.add(t)
for i,(t,u) in enumerate(rows[:24],1): print(f"{i:>2}. {t}\n    {u}\n")
if not rows: print('No news is available right now.')
PY
  rm -f "$tmp"; printf '%sB%s Back\n' "$ACC" "$RESET"; IFS= read -r b || true
  if is_back "$b"; then confirm "Go back?"; fi
}

stocks(){
  title "360 Stocks"; printf '%sTicker%s  › ' "$ACC" "$RESET"; sym="${stocks_prefill:-}"; if [[ -z "${sym// }" ]]; then IFS= read -r sym || true; else printf "%s\n" "$sym"; fi
  if is_back "$sym"; then confirm "Go back?" && return; fi
  [[ -z "${sym// }" ]] && return; sym="${sym^^}"
  local r; spinner_start; r="$(curl -fsSL --max-time 25 "$BASE_URL/stock-data?symbol=$(urlencode "$sym")&range=1d" 2>/dev/null)"; spinner_stop
  if [[ -z "$r" ]]; then printf '%sStock service unavailable.%s\n' "$ERR" "$RESET"; pause; return; fi
  python3 - "$r" "$sym" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); d=x.get('quote',x) if isinstance(x,dict) else {}
def get(*ks):
 for k in ks:
  if d.get(k) is not None:return d[k]
 return None
s=str(get('symbol') or sys.argv[2]).upper(); c=get('companyName','longName','shortName') or s; p=get('lastClose','regularMarketPrice','currentPrice','price'); ch=get('changePct','regularMarketChangePercent','changePercent'); cur=get('currency') or ''
print(f"{c}  ·  {s}\n")
if p is None:
 print(f"  No quote data returned for {s}.")
 if sys.argv[2]=='APPL': print('  Note: AAPL is Apple Inc.; APPL is not its ticker.')
 raise SystemExit
print(f"  Price        {p} {cur}".rstrip())
print(f"  Change       {'+' if ch>=0 else ''}{ch:.2f}%" if isinstance(ch,(int,float)) else '  Change       —')
lo,hi=get('dayLow'),get('dayHigh'); print(f"  Day range    {lo} – {hi}" if lo is not None and hi is not None else '  Day range    —')
lo,hi=get('fiftyTwoWeekLow'),get('fiftyTwoWeekHigh'); print(f"  52-week      {lo} – {hi}" if lo is not None and hi is not None else '  52-week      —')
for label,keys in [('Volume',('volume','regularMarketVolume')),('Avg volume',('avgVolume',)),('Market cap',('marketCap',)),('P/E',('peRatio','trailingPE')),('Sector',('sector',)),('Industry',('industry',))]:
 v=get(*keys)
 if v is not None: print(f"  {label:<12}{v}")
PY
  pause
}

translate(){
  title "360 Translator"; printf '%sText%s  › ' "$ACC" "$RESET"; text="${translate_prefill:-}"; if [[ -z "${text// }" ]]; then IFS= read -r text || true; else printf "%s\n" "$text"; fi
  if is_back "$text"; then confirm "Go back?" && return; fi
  [[ -z "${text// }" ]] && return
  printf '%sFrom [auto]%s › ' "$ACC" "$RESET"; IFS= read -r from || true; if is_back "$from"; then confirm "Go back?" && return; fi; from="${from:-autodetect}"
  printf '%sTo [es]%s › ' "$ACC" "$RESET"; IFS= read -r to || true; if is_back "$to"; then confirm "Go back?" && return; fi; to="${to:-es}"
  local r; spinner_start; r="$(curl -fsSL --max-time 30 "https://api.mymemory.translated.net/get?q=$(urlencode "$text")&langpair=$(urlencode "$from")%7C$(urlencode "$to")" 2>/dev/null)"; spinner_stop
  if [[ -z "$r" ]]; then printf '%sTranslation service unavailable.%s\n' "$ERR" "$RESET"; pause; return; fi
  python3 - "$r" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); print(x.get('responseData',{}).get('translatedText') or x.get('responseDetails') or 'Translation failed.')
PY
  pause
}

shorten(){
  title "360 URL Shortener"; printf '%sURL%s  › ' "$ACC" "$RESET"; url="${shorten_prefill:-}"; if [[ -z "${url// }" ]]; then IFS= read -r url || true; else printf "%s\n" "$url"; fi
  if is_back "$url"; then confirm "Go back?" && return; fi
  [[ -z "${url// }" ]] && return
  local body r; body="$(python3 - "$url" <<'PY'
import json,sys; print(json.dumps({'url':sys.argv[1]}))
PY
)"
  spinner_start
  r="$(curl -fsSL --max-time 30 -X POST "$BASE_URL/smooth-endpoint" -H 'Content-Type: application/json' --data "$body" 2>/dev/null)"; spinner_stop
  if [[ -z "$r" ]]; then printf '%sShortener unavailable.%s\n' "$ERR" "$RESET"; pause; return; fi
  python3 - "$r" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); print(x.get('shortUrl') or x.get('url') or x.get('short_url') or x.get('error') or json.dumps(x,indent=2))
PY
  pause
}

settings(){
  while true; do
    title "360 Settings"
    printf '  %s1%s  Colors: %s%s%s\n' "$ACC" "$RESET" "$BOLD" "$([[ "$COLOR_ENABLED" == 1 ]] && echo On || echo Off)" "$RESET"
    printf '  %s2%s  Accent: %s%s%s\n' "$ACC" "$RESET" "$BOLD" "$ACCENT" "$RESET"
    printf '  %s3%s  Loading: %s%s%s\n' "$ACC" "$RESET" "$BOLD" "$([[ "$LOADING_ENABLED" == 1 ]] && echo On || echo Off)" "$RESET"
    printf '  %s4%s  Animation: %s%s%s\n' "$ACC" "$RESET" "$BOLD" "$LOADING_STYLE" "$RESET"
    printf '  %s5%s  Offline mode: %s%s%s\n' "$ACC" "$RESET" "$BOLD" "$([[ "$OFFLINE_MODE" == 1 ]] && echo On || echo Off)" "$RESET"
    printf '  %s6%s  Back\n\n' "$ACC" "$RESET"
    printf '%s360 settings ›%s ' "$ACC" "$RESET"; IFS= read -r c || return
    if is_back "$c"; then confirm "Go back?" && return; continue; fi
    case "$c" in
      1) [[ "$COLOR_ENABLED" == 1 ]] && COLOR_ENABLED=0 || COLOR_ENABLED=1;;
      2) printf '\n  blue  green  purple  red  yellow  white  cyan\n\nAccent › '; IFS= read -r a || true; if is_back "$a"; then confirm "Go back?" && continue; fi; case "$a" in blue|green|purple|red|yellow|white|cyan) ACCENT="$a";; *) continue;; esac;;
      3) [[ "$LOADING_ENABLED" == 1 ]] && LOADING_ENABLED=0 || LOADING_ENABLED=1;;
      4) printf '\n  loop  dots  bar  pulse\n\nAnimation › '; IFS= read -r a || true; if is_back "$a"; then confirm "Go back?" && continue; fi; case "$a" in loop|dots|bar|pulse) LOADING_STYLE="$a";; *) continue;; esac;;
      5) [[ "$OFFLINE_MODE" == 1 ]] && OFFLINE_MODE=0 || OFFLINE_MODE=1;;
      6) return;;
      *) continue;;
    esac
    printf 'COLOR_ENABLED=%q\nACCENT=%q\nLOADING_ENABLED=%q\nLOADING_STYLE=%q\nOFFLINE_MODE=%q\n' "$COLOR_ENABLED" "$ACCENT" "$LOADING_ENABLED" "$LOADING_STYLE" >"$CONFIG"
    apply_theme
  done

}

menu(){
  clear_screen
  if [[ -f "$BANNER" ]]; then cat "$BANNER"; printf '\n'; fi
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
  printf ' %s12%s  History\n' "$ACC" "$RESET"
  printf ' %s13%s  Status\n\n' "$ACC" "$RESET"
  printf '  %sq%s  Quit\n\n' "$ACC" "$RESET"
  printf '%s360 ›%s ' "$ACC" "$RESET"
}

run_command(){
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    "" ) return 0 ;;
    search|s) cse_search "$*";;
    ai|a) [[ -z "${*// }" ]] && ai || { # prefill AI prompt via stdin-safe temp path
        printf '%s\n' "$*" | ai_cli_arg
      };;
    weather|w) [[ -n "${*// }" ]] && { printf '%s\n' "$*" | weather_arg; } || weather;;
    news) news;;
    stocks) [[ -n "${*// }" ]] && { printf '%s\n' "$*" | stocks_arg; } || stocks;;
    translate|tr)
      if [[ -n "${*// }" ]]; then translate_prefill="$*"; fi
      translate; unset translate_prefill
      ;;
    shorten)
      if [[ -n "${*// }" ]]; then shorten_prefill="$*"; fi
      shorten; unset shorten_prefill
      ;;
    history) show_history;;
    status) show_status;;
    help|-h|--help) show_help;;
    settings) settings;;
    offline)
      [[ "$OFFLINE_MODE" == 1 ]] && OFFLINE_MODE=0 || OFFLINE_MODE=1
      printf 'COLOR_ENABLED=%q\nACCENT=%q\nLOADING_ENABLED=%q\nLOADING_STYLE=%q\nOFFLINE_MODE=%q\n' "$COLOR_ENABLED" "$ACCENT" "$LOADING_ENABLED" "$LOADING_STYLE" "$OFFLINE_MODE" >"$CONFIG"
      printf 'Offline mode: %s\n' "$([[ "$OFFLINE_MODE" == 1 ]] && echo On || echo Off)"
      ;;
    *) printf '%sUnknown command: %s%s\n' "$ERR" "$cmd" "$RESET"; show_help;;
  esac
}

# Lightweight argument-aware wrappers. They preserve the interactive screens while
# allowing `360 search ...`, `360 ai ...`, etc. without duplicating feature implementations.
ai_cli_arg(){ local prompt; IFS= read -r prompt || return; ai_prefill="$prompt"; ai; unset ai_prefill; }
weather_arg(){ local city; IFS= read -r city || return; weather_prefill="$city"; weather; unset weather_prefill; }
stocks_arg(){ local sym; IFS= read -r sym || return; stocks_prefill="$sym"; stocks; unset stocks_prefill; }

if (( $# > 0 )); then
  run_command "$@"
  exit $?
fi

while true; do
  menu
  IFS= read -r choice || exit 0
  case "$choice" in
    1) cse_search;;
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
    12) show_history;;
    13) show_status;;
    q|Q|0) if confirm "Quit 360 CLI?"; then clear_screen; exit 0; fi;;
  esac
done
