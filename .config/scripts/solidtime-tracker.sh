#!/usr/bin/env bash
set -u -o pipefail

# Shared Solidtime controller for the Rofi time-tracker menu and Waybar.
# Credentials stay outside the dotfiles repository. The token file should be
# mode 600; SOLIDTIME_API_TOKEN and SOLIDTIME_API_URL may override them.
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/solidtime"
token_file="${SOLIDTIME_TOKEN_FILE:-$config_dir/waybar-api-token}"
url_file="${SOLIDTIME_URL_FILE:-$config_dir/waybar-api-url}"
host_file="${SOLIDTIME_HOST_FILE:-$config_dir/waybar-api-host}"
organization_file="${SOLIDTIME_ORGANIZATION_FILE:-$config_dir/waybar-api-organization}"
member_file="${SOLIDTIME_MEMBER_FILE:-$config_dir/waybar-api-member}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/solidtime-waybar"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/solidtime-tracker"
break_context_file="$state_dir/break-context.json"
rofi_theme="${ROFI_THEME:-$HOME/.config/rofi/launcher.rasi}"
waybar_signal=8 # Keep in sync with custom/time-tracker.signal in Waybar.

base_url=""
token=""
organization_id=""
member_id=""
projects_file=""
tasks_file=""
active_response_file=""
active_id=""
active_start=""
active_type="work"
active_project_id=""
active_task_id=""
active_organization_id=""
active_description=""
active_project_name=""
active_task_name=""
active_billable="false"
active_found=0
active_offline=0
active_http_code=""
active_available=0
selected_project_id=""
selected_project_name=""
selected_task_id=""
selected_task_name=""
temp_files=()

umask 077

cleanup() {
  local file
  for file in "${temp_files[@]}"; do
    [[ -n "$file" ]] && rm -f -- "$file"
  done
}
trap cleanup EXIT

make_temp() {
  local file
  file="$(mktemp "${TMPDIR:-/tmp}/solidtime-tracker.XXXXXX")" || return 1
  temp_files+=("$file")
  printf '%s\n' "$file"
}

ensure_cache_dir() {
  mkdir -p "$cache_dir" 2>/dev/null || true
  chmod 700 "$cache_dir" 2>/dev/null || true
}

load_base_url() {
  if [[ -n "${SOLIDTIME_API_URL:-}" ]]; then
    base_url="$SOLIDTIME_API_URL"
  elif [[ -r "$url_file" ]]; then
    base_url="$(<"$url_file")"
  else
    return 1
  fi

  base_url="${base_url%/}"
  [[ -n "$base_url" ]]
}

load_token() {
  if [[ -n "${SOLIDTIME_API_TOKEN:-}" ]]; then
    token="$SOLIDTIME_API_TOKEN"
  elif [[ -r "$token_file" ]]; then
    token="$(<"$token_file")"
  else
    return 1
  fi

  [[ -n "$token" ]]
}

load_credentials() {
  load_base_url && load_token
}

format_duration() {
  local total="$1" minutes hours remaining_minutes
  (( total < 0 )) && total=0
  minutes=$((total / 60))
  hours=$((minutes / 60))
  remaining_minutes=$((minutes % 60))
  if (( hours > 0 )); then
    printf '%dh%02dm' "$hours" "$remaining_minutes"
  else
    printf '%dm' "$minutes"
  fi
}

one_line() {
  printf '%s' "$1" | tr '\r\n\t' '   ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

print_idle() {
  local tooltip="${1:-No active task}"
  jq -nc \
    --arg text '󰛊 idle' \
    --arg class 'idle' \
    --arg tooltip "$tooltip" \
    '{text:$text, class:$class, tooltip:$tooltip}'
}

show_error() {
  local message="$1"
  if command -v rofi >/dev/null 2>&1; then
    rofi -e "$message" -theme "$rofi_theme" >/dev/null 2>&1 || true
  else
    printf '%s\n' "$message" >&2
  fi
}

api_request() {
  local method="$1" url="$2" output="$3" body="${4:-}" host_header=""
  local -a curl_args=(
    --silent --show-error
    --connect-timeout 2 --max-time 5
    -X "$method"
    -H "Authorization: Bearer $token"
    -H 'Accept: application/json'
    -o "$output" -w '%{http_code}'
  )

  if [[ "$method" != GET ]]; then
    curl_args+=(-H 'Content-Type: application/json' --data "$body")
  fi

  # The current Tailscale URL is used for connectivity while the instance's
  # legacy trusted hostname is supplied through a private file.
  if [[ -r "$host_file" ]]; then
    host_header="$(<"$host_file")"
    [[ -n "$host_header" ]] && curl_args+=(-H "Host: $host_header")
  fi

  curl "${curl_args[@]}" "$url" 2>/dev/null
}

api_error_message() {
  local response="$1" message=""
  message="$(jq -r '
    if (.message? // null) != null then .message
    elif (.errors? // null) != null then
      [.errors | to_entries[] | .value[]?] | join("; ")
    else empty end
  ' "$response" 2>/dev/null || true)"
  [[ -n "$message" ]] || message='Solidtime request failed'
  one_line "$message"
}

cache_key() {
  printf '%s' "$1" | sha256sum | cut -d' ' -f1
}

valid_active_response() {
  jq -e '(.data.id? != null) and (.data.start? != null)' "$1" >/dev/null 2>&1
}

fetch_active() {
  local output="$1" active_cache="$cache_dir/active.json"

  ensure_cache_dir
  active_found=0
  active_offline=0
  active_available=0
  active_http_code=""

  if ! active_http_code="$(api_request GET "$base_url/api/v1/users/me/time-entries/active" "$output")"; then
    active_http_code=""
    active_offline=1
  elif [[ "$active_http_code" == 404 ]]; then
    # A 404 is a healthy response meaning that no timer is active. Keep the
    # API marked reachable so a subsequent start can resolve memberships.
    active_available=1
    rm -f -- "$active_cache"
    return 0
  elif [[ "$active_http_code" =~ ^2 ]] && valid_active_response "$output"; then
    cp "$output" "$active_cache" 2>/dev/null || true
    active_found=1
    active_available=1
    return 0
  else
    active_offline=1
  fi

  if [[ -s "$active_cache" ]] && valid_active_response "$active_cache"; then
    cp "$active_cache" "$output" 2>/dev/null || true
    active_found=1
    return 0
  fi

  return 1
}

lookup_project_name() {
  local organization="$1" project="$2" cache_file response code name=""
  cache_file="$cache_dir/$(cache_key "$organization/project/$project")"

  if [[ -s "$cache_file" ]]; then
    cat "$cache_file"
    return 0
  fi
  (( active_available )) || return 0

  response="$(make_temp)" || return 0
  code="$(api_request GET "$base_url/api/v1/organizations/$organization/projects/$project" "$response" || true)"
  if [[ "$code" =~ ^2 ]]; then
    name="$(jq -r '.data.name // empty' "$response" 2>/dev/null || true)"
    if [[ -n "$name" ]]; then
      printf '%s\n' "$name" >"$cache_file"
      printf '%s\n' "$name"
    fi
  fi
}

load_tasks_cache() {
  local organization="$1" cache_file response code
  cache_file="$cache_dir/tasks-$organization.json"

  if [[ -s "$cache_file" ]]; then
    tasks_file="$cache_file"
    return 0
  fi
  (( active_available )) || return 1

  response="$(make_temp)" || return 1
  code="$(api_request GET "$base_url/api/v1/organizations/$organization/tasks?done=all&limit=500" "$response" || true)"
  if [[ "$code" =~ ^2 ]] && jq -e '.data | type == "array"' "$response" >/dev/null 2>&1; then
    cp "$response" "$cache_file" 2>/dev/null || true
    tasks_file="$cache_file"
    return 0
  fi

  return 1
}

load_entry_details() {
  local response="$1"

  active_id="$(jq -r '.data.id // empty' "$response" 2>/dev/null || true)"
  active_start="$(jq -r '.data.start // empty' "$response" 2>/dev/null || true)"
  active_type="$(jq -r '.data.type // "work"' "$response" 2>/dev/null || printf 'work')"
  active_project_id="$(jq -r '.data.project_id // empty' "$response" 2>/dev/null || true)"
  active_task_id="$(jq -r '.data.task_id // empty' "$response" 2>/dev/null || true)"
  active_organization_id="$(jq -r '.data.organization_id // empty' "$response" 2>/dev/null || true)"
  active_description="$(jq -r '.data.description // empty' "$response" 2>/dev/null || true)"
  active_billable="$(jq -r '.data.billable // false' "$response" 2>/dev/null || printf 'false')"
  active_project_name=""
  active_task_name=""

  if [[ -n "$active_organization_id" && -n "$active_project_id" ]]; then
    active_project_name="$(lookup_project_name "$active_organization_id" "$active_project_id")"
  fi

  if [[ -n "$active_organization_id" && -n "$active_task_id" ]] && load_tasks_cache "$active_organization_id"; then
    active_task_name="$(jq -r --arg id "$active_task_id" '[.data[]? | select(.id == $id) | .name][0] // empty' "$tasks_file" 2>/dev/null || true)"
  fi

  active_project_name="$(one_line "$active_project_name")"
  active_task_name="$(one_line "$active_task_name")"
}

resolve_membership() {
  local cached_file response code
  organization_id="${SOLIDTIME_ORGANIZATION_ID:-${SOLIDTIME_ORG_ID:-}}"
  member_id="${SOLIDTIME_MEMBER_ID:-}"

  if [[ -z "$organization_id" && -r "$organization_file" ]]; then
    IFS= read -r organization_id <"$organization_file" || true
  fi
  if [[ -z "$member_id" && -r "$member_file" ]]; then
    IFS= read -r member_id <"$member_file" || true
  fi

  if [[ -n "$organization_id" && -n "$member_id" ]]; then
    return 0
  fi

  ensure_cache_dir
  cached_file="$cache_dir/memberships.json"
  if [[ -s "$cached_file" ]]; then
    response="$cached_file"
  elif [[ -n "$base_url" && -n "$token" ]]; then
    response="$(make_temp)" || return 1
    code="$(api_request GET "$base_url/api/v1/users/me/memberships" "$response" || true)"
    if [[ ! "$code" =~ ^2 ]] || ! jq -e '.data | type == "array" and length > 0' "$response" >/dev/null 2>&1; then
      return 1
    fi
    cp "$response" "$cached_file" 2>/dev/null || true
  else
    return 1
  fi

  if [[ -z "$organization_id" ]]; then
    if [[ -n "$member_id" ]]; then
      organization_id="$(jq -r --arg member "$member_id" '[.data[]? | select(.id == $member) | .organization.id][0] // empty' "$response" 2>/dev/null || true)"
    else
      organization_id="$(jq -r '.data[0].organization.id // empty' "$response" 2>/dev/null || true)"
    fi
  fi
  if [[ -z "$member_id" && -n "$organization_id" ]]; then
    member_id="$(jq -r --arg organization "$organization_id" '[.data[]? | select(.organization.id == $organization) | .id][0] // empty' "$response" 2>/dev/null || true)"
  fi

  [[ -n "$organization_id" && -n "$member_id" ]]
}

fetch_projects() {
  local organization="$1" cache_file response code
  cache_file="$cache_dir/projects-$organization.json"
  ensure_cache_dir

  response="$(make_temp)" || return 1
  code="$(api_request GET "$base_url/api/v1/organizations/$organization/projects?limit=500" "$response" || true)"
  if [[ "$code" =~ ^2 ]] && jq -e '.data | type == "array"' "$response" >/dev/null 2>&1; then
    cp "$response" "$cache_file" 2>/dev/null || true
  fi

  if [[ -s "$cache_file" ]] && jq -e '.data | type == "array"' "$cache_file" >/dev/null 2>&1; then
    projects_file="$cache_file"
    return 0
  fi

  return 1
}

prompt_task() {
  local choice task_count
  selected_task_id=""
  selected_task_name=""
  [[ -n "$selected_project_id" ]] || return 0
  load_tasks_cache "$organization_id" || return 0

  task_count="$(jq --arg project "$selected_project_id" '[.data[]? | select(.project_id == $project and (.is_done // false) != true)] | length' "$tasks_file" 2>/dev/null || printf '0')"
  (( task_count > 0 )) || return 0

  choice="$({
    printf '%s\n' '󰄬  No task'
    jq -r --arg project "$selected_project_id" '.data[]? | select(.project_id == $project and (.is_done // false) != true) | .name' "$tasks_file"
  } | rofi -dmenu -i -p 'Task' -mesg 'Optionally narrow the timer to a task.' -theme "$rofi_theme" || true)"
  [[ -n "$choice" ]] || return 1
  if [[ "$choice" == '󰄬  No task' ]]; then
    return 0
  fi

  selected_task_name="$choice"
  selected_task_id="$(jq -r --arg project "$selected_project_id" --arg name "$choice" '[.data[]? | select(.project_id == $project and .name == $name) | .id][0] // empty' "$tasks_file" 2>/dev/null || true)"
  [[ -n "$selected_task_id" ]]
}

prompt_project() {
  local choice no_project_label='󰉋  No project'
  selected_project_id=""
  selected_project_name=""
  selected_task_id=""
  selected_task_name=""

  fetch_projects "$organization_id" || {
    show_error 'Solidtime projects are unavailable'
    return 1
  }

  choice="$({
    printf '%s\n' "$no_project_label"
    jq -r '.data[]? | select((.is_archived // false) != true and (.archived_at // null) == null) | .name' "$projects_file"
  } | rofi -dmenu -i -p 'Project' -mesg 'Choose a Solidtime project.' -theme "$rofi_theme" || true)"
  [[ -n "$choice" ]] || return 1

  if [[ "$choice" != "$no_project_label" ]]; then
    selected_project_name="$choice"
    selected_project_id="$(jq -r --arg name "$choice" '[.data[]? | select(.name == $name and (.is_archived // false) != true and (.archived_at // null) == null) | .id][0] // empty' "$projects_file" 2>/dev/null || true)"
    [[ -n "$selected_project_id" ]] || {
      show_error 'The selected Solidtime project is no longer available'
      return 1
    }
    prompt_task || return 1
  fi
}

start_timer() {
  local project="${1:-}" task="${2:-}" description="${3:-}" billable="${4:-false}"
  local response start payload code

  resolve_membership || {
    show_error 'Solidtime membership is unavailable'
    return 1
  }

  start="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  [[ "$billable" == true ]] || billable=false
  payload="$(jq -nc \
    --arg member "$member_id" \
    --arg project "$project" \
    --arg task "$task" \
    --arg start "$start" \
    --arg description "$description" \
    --argjson billable "$billable" \
    '{member_id:$member, start:$start, end:null, billable:$billable, type:"work"}
     + (if $project != "" then {project_id:$project} else {} end)
     + (if $task != "" then {task_id:$task} else {} end)
     + (if $description != "" then {description:$description} else {} end)')"

  response="$(make_temp)" || return 1
  code="$(api_request POST "$base_url/api/v1/organizations/$organization_id/time-entries" "$response" "$payload" || true)"
  if [[ "$code" =~ ^2 ]]; then
    rm -f -- "$cache_dir/active.json"
    refresh_waybar
    flush_dns_cache
    return 0
  fi

  show_error "Could not start Solidtime timer: $(api_error_message "$response")"
  return 1
}

stop_active_from_file() {
  local response="$1" entry_id organization end payload code
  entry_id="$(jq -r '.data.id // empty' "$response" 2>/dev/null || true)"
  organization="$(jq -r '.data.organization_id // empty' "$response" 2>/dev/null || true)"
  [[ -n "$entry_id" && -n "$organization" ]] || return 1

  end="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  payload="$(jq -nc --arg end "$end" '{end:$end}')"
  response="$(make_temp)" || return 1
  code="$(api_request PUT "$base_url/api/v1/organizations/$organization/time-entries/$entry_id" "$response" "$payload" || true)"
  if [[ "$code" =~ ^2 ]]; then
    rm -f -- "$cache_dir/active.json"
    refresh_waybar
    flush_dns_cache
    return 0
  fi

  show_error "Could not stop Solidtime timer: $(api_error_message "$response")"
  return 1
}

load_active_for_action() {
  local response
  response="$(make_temp)" || return 1
  fetch_active "$response" || return 1
  load_entry_details "$response"
  active_response_file="$response"
  return 0
}

start_from_prompt() {
  local active_was_found="$active_found"

  resolve_membership || {
    show_error 'Solidtime membership is unavailable'
    return 1
  }
  prompt_project || return 0

  if (( active_was_found )); then
    (( active_offline )) && {
      show_error 'Solidtime is offline; the active timer was not changed'
      return 1
    }
    stop_active_from_file "$active_response_file" || return 1
  fi

  start_timer "$selected_project_id" "$selected_task_id"
}

save_break_context() {
  local response="$1"
  mkdir -p "$state_dir" 2>/dev/null || return 1
  jq -c '{project_id:(.data.project_id // ""), task_id:(.data.task_id // ""), description:(.data.description // ""), billable:(.data.billable // false), type:(.data.type // "work")}' \
    "$response" >"$break_context_file" 2>/dev/null
}

stop_for_break() {
  local response
  load_credentials || return 0
  response="$(make_temp)" || return 0
  fetch_active "$response" || return 0
  (( active_found )) || return 0
  (( active_offline )) && return 0
  load_entry_details "$response"
  [[ "$active_type" != break ]] || return 0

  save_break_context "$response" || return 0
  stop_active_from_file "$response" || true
}

restart_after_break() {
  local project task description billable type
  [[ -s "$break_context_file" ]] || return 0
  load_credentials || return 0

  project="$(jq -r '.project_id // empty' "$break_context_file" 2>/dev/null || true)"
  task="$(jq -r '.task_id // empty' "$break_context_file" 2>/dev/null || true)"
  description="$(jq -r '.description // empty' "$break_context_file" 2>/dev/null || true)"
  billable="$(jq -r '.billable // false' "$break_context_file" 2>/dev/null || printf 'false')"
  type="$(jq -r '.type // "work"' "$break_context_file" 2>/dev/null || printf 'work')"
  rm -f -- "$break_context_file"
  [[ "$type" != break ]] || return 0
  start_timer "$project" "$task" "$description" "$billable" || true
}

flush_dns_cache() {
  if command -v resolvectl >/dev/null 2>&1 && systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    resolvectl flush-caches >/dev/null 2>&1 || true
  fi
  pkill -HUP -x dnsmasq 2>/dev/null || true

  # Helium/Chromium can keep blocked 0.0.0.0 answers in its NetworkService.
  pgrep -f '[h]elium.*--type=utility.*network\.mojom\.NetworkService' |
    xargs -r kill 2>/dev/null || true
}

refresh_waybar() {
  # Waybar custom modules configured with `signal` rerun immediately when the
  # matching realtime signal is received. Missing Waybar is harmless.
  pkill "-RTMIN+$waybar_signal" -f '(^|/)waybar($| )' 2>/dev/null || true
}

open_solidtime() {
  local window_id

  if command -v niri >/dev/null 2>&1; then
    window_id="$(niri msg -j windows 2>/dev/null | jq -r '
      [ .[] | select(.app_id == "solidtime") ]
      | if length == 0 then empty else sort_by(.focus_timestamp.secs, .focus_timestamp.nanos) | last.id end
    ' 2>/dev/null || true)"
    if [[ -n "$window_id" ]]; then
      niri msg action focus-window --id "$window_id" >/dev/null 2>&1 || true
      return 0
    fi
  fi

  command -v solidtime >/dev/null 2>&1 || return 0
  solidtime >/dev/null 2>&1 &

  command -v niri >/dev/null 2>&1 || return 0
  for _ in {1..10}; do
    window_id="$(niri msg -j windows 2>/dev/null | jq -r '
      [ .[] | select(.app_id == "solidtime") ]
      | if length == 0 then empty else sort_by(.focus_timestamp.secs, .focus_timestamp.nanos) | last.id end
    ' 2>/dev/null || true)"
    if [[ -n "$window_id" ]]; then
      niri msg action focus-window --id "$window_id" >/dev/null 2>&1 || true
      return 0
    fi
    sleep 0.1
  done
}

print_status() {
  local response start_epoch now_epoch elapsed formatted started_at tooltip label text class

  if ! load_base_url; then
    print_idle 'Solidtime URL is not configured'
    return 0
  fi
  if ! load_token; then
    print_idle 'Solidtime token is not configured'
    return 0
  fi

  response="$(make_temp)" || {
    print_idle 'Solidtime unavailable'
    return 0
  }
  if ! fetch_active "$response"; then
    print_idle 'Solidtime unavailable'
    return 0
  fi
  if (( ! active_found )); then
    print_idle
    return 0
  fi

  load_entry_details "$response"
  start_epoch="$(date -d "$active_start" +%s 2>/dev/null || true)"
  if [[ ! "$start_epoch" =~ ^[0-9]+$ ]]; then
    print_idle 'Solidtime returned an invalid timer'
    return 0
  fi

  now_epoch="$(date +%s)"
  elapsed=$((now_epoch - start_epoch))
  (( elapsed < 0 )) && elapsed=0
  formatted="$(format_duration "$elapsed")"
  started_at="$(date -d "$active_start" '+%H:%M' 2>/dev/null || true)"

  if [[ -n "$active_task_name" ]]; then
    label="$active_task_name"
    [[ -n "$active_project_name" ]] && label+=" (${active_project_name})"
  elif [[ -n "$active_project_name" ]]; then
    label="$active_project_name"
  elif [[ -n "$active_description" ]]; then
    label="$(one_line "$active_description")"
  else
    label='no project'
  fi

  if [[ "${active_type,,}" == break ]]; then
    tooltip="${formatted} break"
    text="󰛊 break ${formatted}"
    class='break'
  else
    text="󱎫 ${label} ${formatted}"
    class='running'
    if [[ -n "$started_at" ]]; then
      tooltip="${formatted} current · started ${started_at}"
    else
      tooltip="${formatted} current"
    fi
    tooltip+=$'\n'"$label"
  fi
  (( active_offline )) && tooltip+=" · last known"

  jq -nc \
    --arg text "$text" \
    --arg class "$class" \
    --arg tooltip "$tooltip" \
    '{text:$text, class:$class, tooltip:$tooltip}'
}

show_menu() {
  local status_line choice elapsed start_epoch now_epoch
  local stop_label='󰐥  Stop timer'
  local start_label='󰜉  Start timer'
  local switch_label='󰜉  Switch project'
  local open_label='󰛊  Open Solidtime'

  if ! load_credentials; then
    show_error 'Solidtime URL or token is not configured'
    return 0
  fi
  if ! load_active_for_action; then
    show_error 'Solidtime is unavailable'
    return 0
  fi

  if (( active_found )); then
    start_epoch="$(date -d "$active_start" +%s 2>/dev/null || printf '0')"
    now_epoch="$(date +%s)"
    elapsed=$((now_epoch - start_epoch))
    (( elapsed < 0 )) && elapsed=0
    status_line="${active_project_name:-No project} · $(format_duration "$elapsed")"
    [[ -n "$active_task_name" ]] && status_line+=" · ${active_task_name}"
    [[ "${active_type,,}" == break ]] && status_line="Break · $(format_duration "$elapsed")"
    (( active_offline )) && status_line+=' · last known'

    choice="$({ printf '%s\n' "$stop_label" "$switch_label" "$open_label"; } |
      rofi -dmenu -i -p 'Time tracker' -mesg "$status_line" -theme "$rofi_theme" || true)"
    case "$choice" in
      "$stop_label")
        (( active_offline )) || stop_active_from_file "$active_response_file" || true
        ;;
      "$switch_label")
        (( active_offline )) && show_error 'Solidtime is offline; the active timer was not changed' || start_from_prompt
        ;;
      "$open_label")
        open_solidtime
        ;;
    esac
  else
    choice="$({ printf '%s\n' "$start_label" "$open_label"; } |
      rofi -dmenu -i -p 'Time tracker' -mesg 'No active Solidtime timer' -theme "$rofi_theme" || true)"
    case "$choice" in
      "$start_label") start_from_prompt ;;
      "$open_label") open_solidtime ;;
    esac
  fi
}

command_name="${1:-menu}"
case "$command_name" in
  status)
    print_status
    ;;
  open)
    load_base_url || true
    open_solidtime
    ;;
  start)
    load_credentials || { show_error 'Solidtime URL or token is not configured'; exit 0; }
    load_active_for_action || { show_error 'Solidtime is unavailable'; exit 0; }
    if (( active_found && active_offline )); then
      show_error 'Solidtime is offline; the active timer was not changed'
    elif [[ -n "${2:-}" || -n "${3:-}" ]]; then
      if (( active_found )); then
        stop_active_from_file "$active_response_file" || true
      fi
      start_timer "${2:-}" "${3:-}"
    else
      start_from_prompt
    fi
    ;;
  stop)
    if load_credentials; then
      load_active_for_action && (( active_found && !active_offline )) && stop_active_from_file "$active_response_file" || true
    fi
    ;;
  pause-for-lock|stop-for-break)
    stop_for_break
    ;;
  resume-after-lock|restart-after-break)
    restart_after_break
    ;;
  # Compatibility for processes that loaded the old command path before this
  # split. Power and lock behavior lives in session-power.sh.
  lock)
    exec "$HOME/.config/scripts/session-power.sh" lock
    ;;
  systemctl-break)
    shift
    exec "$HOME/.config/scripts/session-power.sh" "$@"
    ;;
  menu|*)
    show_menu
    ;;
esac
