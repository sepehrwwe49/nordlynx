#!/usr/bin/env bash
# ==============================================================================
#  NordLynx Manager — Telegram bot
#  Remote control for the container fleet: tokens, new locations, live status.
#
#  Installed and supervised by nordlynx-manager.sh (menu 17).
#  Config: /opt/nordlynx-manager/telegram.env   (TG_BOT_TOKEN, TG_ADMINS)
#
#  License: MIT
# ==============================================================================
set -uo pipefail

MANAGER="${NLM_MANAGER:-/usr/local/bin/nordlynx}"
[[ -x "$MANAGER" ]] || MANAGER="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/nordlynx-manager.sh"

# Pull in the manager as a library: tokens, containers, cfg_create, countries…
NLM_LIB=1 . "$MANAGER" || { echo "cannot source manager: $MANAGER"; exit 1; }

tg_load
if [[ "${NLM_BOT_LIB:-0}" != "1" ]]; then
  [[ -n "${TG_BOT_TOKEN:-}" ]] || { echo "TG_BOT_TOKEN missing in $TG_CONF"; exit 1; }
fi
have jq   || { echo "jq is required (run menu option 1)"; exit 1; }
have curl || { echo "curl is required"; exit 1; }

mkdir -p "$BOT_STATE"; chmod 700 "$BOT_STATE"
API="https://api.telegram.org/bot${TG_BOT_TOKEN}"

# ------------------------------------------------------------------ helpers --
api() { curl -s -m 60 "$API/$1" "${@:2}"; }
esc() { local s="$1"; s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; printf '%s' "$s"; }

# mk_kb "Label=cbdata|Label2=cbdata2" "Row2Label=cb" …
mk_kb() {
  local rows=() row btns btn text data json parts
  for row in "$@"; do
    btns=()
    IFS='|' read -r -a parts <<<"$row"
    for btn in "${parts[@]}"; do
      text="${btn%%=*}"; data="${btn#*=}"
      btns+=("$(jq -nc --arg t "$text" --arg d "$data" '{text:$t,callback_data:$d}')")
    done
    rows+=("[$(IFS=,; echo "${btns[*]}")]")
  done
  json="$(IFS=,; echo "${rows[*]}")"
  printf '{"inline_keyboard":[%s]}' "$json"
}

send() {   # send <chat> <html-text> [keyboard]
  local chat="$1" text="$2" kb="${3:-}"
  if [[ -n "$kb" ]]; then
    api sendMessage -d chat_id="$chat" -d parse_mode=HTML -d disable_web_page_preview=true \
      --data-urlencode "text=$text" --data-urlencode "reply_markup=$kb" >/dev/null
  else
    api sendMessage -d chat_id="$chat" -d parse_mode=HTML -d disable_web_page_preview=true \
      --data-urlencode "text=$text" >/dev/null
  fi
}

edit() {   # edit <chat> <msg_id> <html-text> [keyboard]
  local chat="$1" mid="$2" text="$3" kb="${4:-}"
  if [[ -n "$kb" ]]; then
    api editMessageText -d chat_id="$chat" -d message_id="$mid" -d parse_mode=HTML \
      -d disable_web_page_preview=true \
      --data-urlencode "text=$text" --data-urlencode "reply_markup=$kb" >/dev/null
  else
    api editMessageText -d chat_id="$chat" -d message_id="$mid" -d parse_mode=HTML \
      -d disable_web_page_preview=true --data-urlencode "text=$text" >/dev/null
  fi
}

answer() { api answerCallbackQuery -d callback_query_id="$1" --data-urlencode "text=${2:-}" >/dev/null; }

is_admin() { tg_admin_list | grep -qx "$1"; }

# ------------------------------------------------------------------- state ---
st_file() { printf '%s/%s.env' "$BOT_STATE" "$1"; }
st_set()  { local f; f="$(st_file "$1")"; touch "$f"; chmod 600 "$f"
            local tmp; tmp="$(mktemp)"; grep -v "^$2=" "$f" >"$tmp" 2>/dev/null
            printf '%s=%s\n' "$2" "$3" >>"$tmp"; mv "$tmp" "$f"; chmod 600 "$f"; }
st_get()  { local f; f="$(st_file "$1")"; [[ -f "$f" ]] && sed -n "s/^$2=//p" "$f" | tail -1; }
st_clear(){ rm -f "$(st_file "$1")"; }

# ------------------------------------------------------------------- views ---
kb_main() {
  mk_kb "🔑 Access tokens=m:tok|➕ New location=m:new" \
        "📋 Locations=m:list|♻️ Refresh=m:main"
}

view_main() {   # view_main <chat> [msg_id]
  local chat="$1" mid="${2:-}"
  local locs tokens running
  locs="$(list_locations | grep -c . || true)"
  tokens="$(tok_count)"
  running="$(docker ps --filter "label=${LABEL_NS}.managed=1" --format '{{.Names}}' | grep -c . || true)"
  local text
  text="<b>NordLynx Manager</b>
<code>v${VERSION}</code>

🔑 tokens: <b>${tokens}</b>
📦 locations: <b>${locs}</b>  (running: <b>${running}</b>)

Choose an action:"
  if [[ -n "$mid" ]]; then edit "$chat" "$mid" "$text" "$(kb_main)"
  else send "$chat" "$text" "$(kb_main)"; fi
}

view_tokens() {
  local chat="$1" mid="${2:-}"
  local -a names=(); mapfile -t names < <(tok_names)
  local text="<b>🔑 Access tokens</b>

" rows=() i used
  if (( ${#names[@]} == 0 )); then
    text+="<i>No tokens stored yet.</i>"
  else
    for i in "${!names[@]}"; do
      used="$(list_locations | awk -F'\t' -v n="${names[$i]}" '$9==n' | grep -c . || true)"
      text+="• <b>$(esc "${names[$i]}")</b> — <code>$(esc "$(tok_mask "$(tok_get "${names[$i]}")")")</code> — ${used} location(s)
"
    done
  fi
  rows+=("➕ Add token=tk:add")
  (( ${#names[@]} > 0 )) && rows+=("🗑 Remove token=tk:delmenu")
  rows+=("⬅️ Back=m:main")
  local kb; kb="$(mk_kb "${rows[@]}")"
  if [[ -n "$mid" ]]; then edit "$chat" "$mid" "$text" "$kb"; else send "$chat" "$text" "$kb"; fi
}

view_token_del() {
  local chat="$1" mid="$2"
  local -a names=(); mapfile -t names < <(tok_names)
  local rows=() n
  for n in "${names[@]}"; do rows+=("🗑 $n=tk:del:$n"); done
  rows+=("⬅️ Back=m:tok")
  edit "$chat" "$mid" "<b>Remove which token?</b>
The containers already built with it keep working." "$(mk_kb "${rows[@]}")"
}

# ---- new location wizard -----------------------------------------------------
view_new_token() {
  local chat="$1" mid="$2"
  local -a names=(); mapfile -t names < <(tok_names)
  if (( ${#names[@]} == 0 )); then
    edit "$chat" "$mid" "<b>No access tokens yet.</b>
Add one first." "$(mk_kb "➕ Add token=tk:add" "⬅️ Back=m:main")"
    return
  fi
  local rows=() n
  for n in "${names[@]}"; do rows+=("🔑 $n=nw:tok:$n"); done
  rows+=("⬅️ Back=m:main")
  edit "$chat" "$mid" "<b>➕ New location — step 1/4</b>
Pick the access token to build it with:" "$(mk_kb "${rows[@]}")"
}

view_new_country() {
  local chat="$1" mid="$2"
  local rows=() e code flag label pair=""
  for e in "${COUNTRIES[@]}"; do
    IFS='|' read -r code flag label <<<"$e"
    if [[ -z "$pair" ]]; then pair="$flag $label=nw:cty:$code"
    else rows+=("$pair|$flag $label=nw:cty:$code"); pair=""; fi
  done
  [[ -n "$pair" ]] && rows+=("$pair")
  rows+=("⬅️ Back=m:new")
  edit "$chat" "$mid" "<b>➕ New location — step 2/4</b>
Pick a country:" "$(mk_kb "${rows[@]}")"
}

view_new_city() {
  local chat="$1" mid="$2" country="$3"
  local -a cities=(); mapfile -t cities < <(cities_of "$country" 2>/dev/null)
  if (( ${#cities[@]} == 0 )); then
    st_set "$chat" NEW_CITY ""
    view_new_port "$chat" "$mid"; return
  fi
  printf '%s\n' "${cities[@]}" >"$BOT_STATE/$chat.cities"
  local rows=() i pair=""
  for i in "${!cities[@]}"; do
    if [[ -z "$pair" ]]; then pair="${cities[$i]}=nw:city:$i"
    else rows+=("$pair|${cities[$i]}=nw:city:$i"); pair=""; fi
  done
  [[ -n "$pair" ]] && rows+=("$pair")
  rows+=("🌍 Any city=nw:city:any")
  rows+=("⬅️ Back=m:new")
  edit "$chat" "$mid" "<b>➕ New location — step 3/4</b>
Country: <b>$(esc "$country")</b>
Pick a city (or let NordVPN choose):" "$(mk_kb "${rows[@]}")"
}

view_new_port() {
  local chat="$1" mid="$2"
  local sug1 sug2 sug3
  sug1="$(next_free_port)"
  sug2="$sug1"; while port_in_use "$sug2" || [[ "$sug2" == "$sug1" ]]; do sug2=$(( sug2 + 1 )); done
  sug3="$sug2"; while port_in_use "$sug3" || [[ "$sug3" == "$sug2" ]]; do sug3=$(( sug3 + 1 )); done
  local country city
  country="$(st_get "$chat" NEW_COUNTRY)"; city="$(st_get "$chat" NEW_CITY)"
  edit "$chat" "$mid" "<b>➕ New location — step 4/4</b>
Country: <b>$(esc "$country")</b>
City: <b>$(esc "${city:-any}")</b>

Pick a host port for the SOCKS5 endpoint:" \
    "$(mk_kb "$sug1=nw:port:$sug1|$sug2=nw:port:$sug2|$sug3=nw:port:$sug3" \
             "⌨️ Type a port=nw:portask" "⬅️ Back=m:new")"
}

# ---- locations ---------------------------------------------------------------
view_list() {
  local chat="$1" mid="${2:-}"
  local rows=() n c p b s tech proto ipn tokn city dot
  local text="<b>📋 Locations</b>

"
  local any=0
  while IFS=$'\t' read -r n c p b s tech proto ipn tokn city; do
    [[ -z "$n" ]] && continue
    any=1
    dot="🔴"; [[ "$s" == "running" ]] && dot="🟢"
    text+="${dot} <b>$(esc "$n")</b> — $(esc "$c") — <code>${b}:${p}</code>
"
    rows+=("${dot} ${c} :${p}=l:$n")
  done < <(list_locations)
  (( any )) || text+="<i>Nothing built yet.</i>"
  rows+=("➕ New location=m:new" "⬅️ Back=m:main")
  local kb; kb="$(mk_kb "${rows[@]}")"
  if [[ -n "$mid" ]]; then edit "$chat" "$mid" "$text" "$kb"; else send "$chat" "$text" "$kb"; fi
}

uptime_of() {
  local started; started="$(docker inspect "$1" --format '{{.State.StartedAt}}' 2>/dev/null)"
  [[ -z "$started" ]] && { printf '—'; return; }
  local s0 now d h m
  s0="$(date -d "$started" +%s 2>/dev/null)" || { printf '—'; return; }
  now="$(date +%s)"; local diff=$(( now - s0 ))
  (( diff < 0 )) && diff=0
  d=$(( diff / 86400 )); h=$(( (diff % 86400) / 3600 )); m=$(( (diff % 3600) / 60 ))
  if (( d > 0 )); then printf '%dd %dh %dm' "$d" "$h" "$m"
  elif (( h > 0 )); then printf '%dh %dm' "$h" "$m"
  else printf '%dm' "$m"; fi
}

view_loc() {
  local chat="$1" mid="$2" name="$3"
  if ! docker inspect "$name" >/dev/null 2>&1; then
    edit "$chat" "$mid" "<b>Gone.</b> That container no longer exists." "$(mk_kb "⬅️ Back=m:list")"
    return
  fi
  cfg_load "$name"
  local state up nstat server ncountry ncity tech proto
  state="$(docker inspect "$name" --format '{{.State.Status}}' 2>/dev/null)"
  up="$(uptime_of "$name")"
  local raw=""
  [[ "$state" == "running" ]] && raw="$(docker exec "$name" nordvpn status 2>/dev/null || true)"
  nstat="$(awk -F': ' '/Status/{print $2; exit}'   <<<"$raw" | tr -d '\r')"
  server="$(awk -F': ' '/Hostname/{print $2; exit}' <<<"$raw" | tr -d '\r')"
  ncountry="$(awk -F': ' '/Country/{print $2; exit}' <<<"$raw" | tr -d '\r')"
  ncity="$(awk -F': ' '/City/{print $2; exit}'      <<<"$raw" | tr -d '\r')"
  tech="${CFG[tech]}"; proto="${CFG[proto]}"
  [[ "$tech" == "NordLynx" ]] && proto="UDP"

  local text
  text="<b>$(esc "$name")</b>

🔑 token: <b>$(esc "${CFG[token]:-—}")</b>
🌍 configured: <b>$(esc "${CFG[country]}")</b>$( [[ -n "${CFG[city]}" ]] && printf ' / %s' "$(esc "${CFG[city]}")" )
🔌 protocol: <b>${tech}</b> / ${proto}
🧦 socks5: <code>${CFG[bind]}:${CFG[hport]}</code> → container <code>${CFG[iport]}</code>
📦 docker: <b>${state}</b>
⏱ uptime: <b>${up}</b>

<b>NordVPN</b>
status: <b>$(esc "${nstat:-unknown}")</b>
connected to: <b>$(esc "${ncountry:-—}")$( [[ -n "$ncity" ]] && printf ' / %s' "$(esc "$ncity")" )</b>
server: <code>$(esc "${server:-—}")</code>"

  edit "$chat" "$mid" "$text" \
    "$(mk_kb "🔢 Change port=l:port:$name|🌍 Change location=l:loc:$name" \
             "📤 Export socks outbound=l:out:$name" \
             "♻️ Refresh=l:$name|⬅️ Back=m:list")"
}

view_loc_country() {
  local chat="$1" mid="$2" name="$3"
  local rows=() e code flag label pair=""
  for e in "${COUNTRIES[@]}"; do
    IFS='|' read -r code flag label <<<"$e"
    if [[ -z "$pair" ]]; then pair="$flag $label=cc:$code"
    else rows+=("$pair|$flag $label=cc:$code"); pair=""; fi
  done
  [[ -n "$pair" ]] && rows+=("$pair")
  rows+=("⬅️ Back=l:$name")
  edit "$chat" "$mid" "<b>🌍 Change location of</b> <code>$(esc "$name")</code>

The container is rebuilt with the same name and the same host port,
so your Marzban config keeps working.

Pick the new country:" "$(mk_kb "${rows[@]}")"
}

# ---- work: rebuild / create --------------------------------------------------
run_create() {   # run_create <chat> — CFG must be filled; reports progress
  local chat="$1" name="${CFG[name]}"
  local msg
  msg="$(api sendMessage -d chat_id="$chat" -d parse_mode=HTML \
        --data-urlencode "text=⏳ Building <b>$(esc "${CFG[country]}")</b> on port <b>${CFG[hport]}</b>…
This usually takes 30–90 seconds." | jq -r '.result.message_id')"

  local out rc
  out="$(cfg_create 2>&1)"; rc=$?

  # cfg_create picks the name itself when CFG[name] was empty
  [[ -z "$name" ]] && name="$(list_locations | awk -F'\t' -v p="${CFG[hport]}" '$3==p {print $1; exit}')"

  if (( rc == 0 )); then
    local ip; ip="$(curl -s --max-time 15 --proxy "socks5h://127.0.0.1:${CFG[hport]}" https://api.ipify.org || true)"
    edit "$chat" "$msg" "✅ <b>$(esc "$name")</b> is up.
🌍 $(esc "${CFG[country]}")$( [[ -n "${CFG[city]}" ]] && printf ' / %s' "$(esc "${CFG[city]}")" )
🧦 <code>${CFG[bind]}:${CFG[hport]}</code>
🌐 exit IP: <code>$(esc "${ip:-unknown}")</code>"
  else
    edit "$chat" "$msg" "❌ Build failed.
<pre>$(esc "$(printf '%s' "$out" | tail -c 800)")</pre>"
  fi
  view_main "$chat"
}

outbound_json() {   # outbound_json <name>
  cfg_load "$1"
  local tag; tag="$(printf '%s' "${CFG[country]}" | tr '[:lower:]' '[:upper:]')"
  cat <<JSON
{
  "tag": "NORD-${tag}",
  "protocol": "socks",
  "settings": { "servers": [ { "address": "127.0.0.1", "port": ${CFG[hport]} } ] },
  "streamSettings": { "network": "tcp" }
}
JSON
}

# ------------------------------------------------------------------ router ---
handle_callback() {
  local chat="$1" mid="$2" cbid="$3" data="$4"
  case "$data" in
    m:main)  answer "$cbid"; view_main   "$chat" "$mid" ;;
    m:tok)   answer "$cbid"; view_tokens "$chat" "$mid" ;;
    m:list)  answer "$cbid"; view_list   "$chat" "$mid" ;;
    m:new)   answer "$cbid"; st_clear "$chat"; view_new_token "$chat" "$mid" ;;

    tk:add)  answer "$cbid"
             st_set "$chat" AWAIT token_name
             edit "$chat" "$mid" "<b>➕ New access token</b>

Send me a short <b>name</b> for it (for example <code>main</code> or <code>client-a</code>)." \
               "$(mk_kb "✖️ Cancel=m:tok")" ;;
    tk:delmenu) answer "$cbid"; view_token_del "$chat" "$mid" ;;
    tk:del:*)   local n="${data#tk:del:}"; tok_del "$n"; answer "$cbid" "removed"
                view_tokens "$chat" "$mid" ;;

    nw:tok:*)  local n="${data#nw:tok:}"; st_set "$chat" NEW_TOKEN "$n"
               answer "$cbid"; view_new_country "$chat" "$mid" ;;
    nw:cty:*)  local c="${data#nw:cty:}"; st_set "$chat" NEW_COUNTRY "$c"
               answer "$cbid" "reading cities…"; view_new_city "$chat" "$mid" "$c" ;;
    nw:city:any) st_set "$chat" NEW_CITY ""; answer "$cbid"; view_new_port "$chat" "$mid" ;;
    nw:city:*) local idx="${data#nw:city:}" city
               city="$(sed -n "$(( idx + 1 ))p" "$BOT_STATE/$chat.cities" 2>/dev/null)"
               st_set "$chat" NEW_CITY "$city"; answer "$cbid"; view_new_port "$chat" "$mid" ;;
    nw:portask) st_set "$chat" AWAIT new_port; answer "$cbid"
               edit "$chat" "$mid" "Send me the host port number (1024–65535)." "$(mk_kb "✖️ Cancel=m:main")" ;;
    nw:port:*) local p="${data#nw:port:}"
               if port_in_use "$p"; then answer "$cbid" "port $p is busy"; view_new_port "$chat" "$mid"; return; fi
               answer "$cbid" "building…"
               cfg_reset
               CFG[token]="$(st_get "$chat" NEW_TOKEN)"
               CFG[country]="$(st_get "$chat" NEW_COUNTRY)"
               CFG[city]="$(st_get "$chat" NEW_CITY)"
               CFG[hport]="$p"
               st_clear "$chat"
               run_create "$chat" ;;

    l:port:*)  local n="${data#l:port:}"; st_set "$chat" TARGET "$n"; st_set "$chat" AWAIT loc_port
               answer "$cbid"
               edit "$chat" "$mid" "<b>🔢 Change port of</b> <code>$(esc "$n")</code>

Send me the new host port. The container is rebuilt with the same country." \
                 "$(mk_kb "✖️ Cancel=l:$n")" ;;
    l:out:*)   local n="${data#l:out:}"; answer "$cbid"
               send "$chat" "<b>📤 Xray outbound for</b> <code>$(esc "$n")</code>
<pre>$(esc "$(outbound_json "$n")")</pre>
Paste it into the Marzban / Pasarguard core config, then route to the tag." \
                 "$(mk_kb "⬅️ Back=l:$n")" ;;
    l:loc:*)   local n="${data#l:loc:}"; st_set "$chat" TARGET "$n"; answer "$cbid"
               view_loc_country "$chat" "$mid" "$n" ;;
    l:*)       local n="${data#l:}"; answer "$cbid"; view_loc "$chat" "$mid" "$n" ;;

    cc:*)      local c="${data#cc:}" n; n="$(st_get "$chat" TARGET)"
               [[ -z "$n" ]] && { answer "$cbid" "expired"; view_main "$chat" "$mid"; return; }
               answer "$cbid" "rebuilding…"
               cfg_load "$n"
               CFG[country]="$c"; CFG[city]=""; CFG[name]="$n"
               edit "$chat" "$mid" "♻️ Rebuilding <code>$(esc "$n")</code> in <b>$(esc "$c")</b>…"
               docker rm -f "$n" >/dev/null 2>&1
               st_clear "$chat"
               run_create "$chat" ;;

    *) answer "$cbid" "unknown action" ;;
  esac
}

handle_text() {
  local chat="$1" text="$2"
  local await; await="$(st_get "$chat" AWAIT)"

  case "$text" in
    /start|/menu) st_clear "$chat"; view_main "$chat"; return ;;
    /list)  view_list "$chat"; return ;;
    /id)    send "$chat" "Your Telegram ID: <code>$chat</code>"; return ;;
  esac

  case "$await" in
    token_name)
      local name; name="$(printf '%s' "$text" | tr -cd 'A-Za-z0-9._-')"
      [[ -z "$name" ]] && { send "$chat" "That name has no usable characters. Try again."; return; }
      st_set "$chat" TOK_NAME "$name"; st_set "$chat" AWAIT token_value
      send "$chat" "Name: <b>$(esc "$name")</b>
Now send the <b>access token</b> itself.
<i>Nord Account → Services → NordVPN → Manual setup → Generate new token</i>" ;;
    token_value)
      local tokv name
      tokv="$(printf '%s' "$text" | tr -d '[:space:]')"
      name="$(st_get "$chat" TOK_NAME)"
      if [[ -z "$tokv" ]]; then send "$chat" "Empty — nothing saved."; return; fi
      tok_add "$name" "$tokv"
      st_clear "$chat"
      send "$chat" "✅ Saved as <b>$(esc "$name")</b>.
🔒 Delete your message with the token from this chat — Telegram keeps history."
      view_tokens "$chat" ;;
    new_port)
      local p; p="$(printf '%s' "$text" | tr -cd '0-9')"
      if [[ -z "$p" ]] || (( p < 1 || p > 65535 )); then send "$chat" "Not a valid port."; return; fi
      if port_in_use "$p"; then send "$chat" "Port <b>$p</b> is already in use."; return; fi
      cfg_reset
      CFG[token]="$(st_get "$chat" NEW_TOKEN)"
      CFG[country]="$(st_get "$chat" NEW_COUNTRY)"
      CFG[city]="$(st_get "$chat" NEW_CITY)"
      CFG[hport]="$p"
      st_clear "$chat"
      run_create "$chat" ;;
    loc_port)
      local p n; p="$(printf '%s' "$text" | tr -cd '0-9')"; n="$(st_get "$chat" TARGET)"
      if [[ -z "$p" ]] || (( p < 1 || p > 65535 )); then send "$chat" "Not a valid port."; return; fi
      if port_in_use "$p"; then send "$chat" "Port <b>$p</b> is already in use."; return; fi
      cfg_load "$n"; CFG[hport]="$p"; CFG[name]="$n"
      st_clear "$chat"
      send "$chat" "♻️ Rebuilding <code>$(esc "$n")</code> on port <b>$p</b>…"
      docker rm -f "$n" >/dev/null 2>&1
      run_create "$chat" ;;
    *)
      view_main "$chat" ;;
  esac
}

# -------------------------------------------------------------------- loop ---
# Sourced with NLM_BOT_LIB=1 for tests → stop before the polling loop.
if [[ "${NLM_BOT_LIB:-0}" == "1" ]]; then return 0 2>/dev/null || exit 0; fi

printf 'nordlynx-bot: starting, admins: %s\n' "$(tg_admin_list | paste -sd, -)"
api deleteWebhook >/dev/null 2>&1
OFFSET=0

while true; do
  resp="$(api getUpdates -d offset="$OFFSET" -d timeout=30 \
          --data-urlencode 'allowed_updates=["message","callback_query"]')"
  [[ -z "$resp" ]] && { sleep 3; continue; }
  if [[ "$(jq -r '.ok // false' <<<"$resp")" != "true" ]]; then
    printf 'telegram error: %s\n' "$(jq -c '.' <<<"$resp" | head -c 300)"
    sleep 5; continue
  fi

  mapfile -t updates < <(jq -c '.result[]?' <<<"$resp")
  for u in "${updates[@]}"; do
    OFFSET=$(( $(jq -r '.update_id' <<<"$u") + 1 ))

    if [[ "$(jq -r 'has("callback_query")' <<<"$u")" == "true" ]]; then
      from="$(jq -r '.callback_query.from.id'          <<<"$u")"
      chat="$(jq -r '.callback_query.message.chat.id'  <<<"$u")"
      mid="$(jq  -r '.callback_query.message.message_id' <<<"$u")"
      cbid="$(jq -r '.callback_query.id'               <<<"$u")"
      data="$(jq -r '.callback_query.data // ""'       <<<"$u")"
      if ! is_admin "$from"; then answer "$cbid" "not authorised"; continue; fi
      handle_callback "$chat" "$mid" "$cbid" "$data"
    else
      from="$(jq -r '.message.from.id // ""'  <<<"$u")"
      chat="$(jq -r '.message.chat.id // ""'  <<<"$u")"
      text="$(jq -r '.message.text // ""'     <<<"$u")"
      [[ -z "$chat" ]] && continue
      if ! is_admin "$from"; then
        send "$chat" "⛔️ Not authorised.
Your Telegram ID is <code>$from</code> — ask the server owner to add it."
        continue
      fi
      handle_text "$chat" "$text"
    fi
  done
done
