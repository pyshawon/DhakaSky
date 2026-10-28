#!/usr/bin/env bash
# Claude Code status line — colorful with emojis, usage info & progress bar

input=$(cat)

# ANSI colors
RST="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
MAGENTA="\033[35m"
CYAN="\033[36m"
WHITE="\033[37m"

# ---------------------------------------------------------------------------
# Helper: format token counts (1234567 -> 1.2M, 12345 -> 12.3k)
# ---------------------------------------------------------------------------
fmt_tokens() {
  local n="${1:-0}"
  if [ "$n" -ge 1000000 ] 2>/dev/null; then
    printf '%.1fM' "$(echo "scale=1; $n/1000000" | bc)"
  elif [ "$n" -ge 1000 ] 2>/dev/null; then
    printf '%.1fk' "$(echo "scale=1; $n/1000" | bc)"
  else
    printf '%s' "$n"
  fi
}

# ---------------------------------------------------------------------------
# Helper: progress bar  ████░░░░░░ 42%
# ---------------------------------------------------------------------------
progress_bar() {
  local pct="${1:-0}"
  local width="${2:-15}"
  local color="$3"
  local filled=$(echo "$pct * $width / 100" | bc 2>/dev/null || echo 0)
  local empty=$((width - filled))
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done
  printf '%b%s%b' "$color" "$bar" "$RST"
}

# ---------------------------------------------------------------------------
# Model
# ---------------------------------------------------------------------------
model_name=$(echo "$input" | jq -r '.model.display_name // ""')
context_size=$(echo "$input" | jq -r '
  .context_window.context_window_size // 0 |
  if . >= 1000000 then "\(. / 1000000 | floor)M"
  elif . >= 1000 then "\(. / 1000 | floor)k"
  else "\(.)"
  end
')

# Read configured default effort from settings.json
settings_file="$HOME/.claude/settings.json"
default_effort="medium"
if [ -f "$settings_file" ]; then
  configured_effort=$(jq -r '.effortLevel // ""' "$settings_file" 2>/dev/null)
  [ -n "$configured_effort" ] && default_effort="$configured_effort"
fi

# Determine if model is default for current effort
raw_effort=$(echo "$input" | jq -r '.output_style.name // ""')
is_default=""
if [ -n "$model_name" ]; then
  if [[ "$model_name" == *"Haiku"* ]]; then
    is_default=" ${DIM}(default)${RST}"
  elif [[ "$model_name" == *"Sonnet"* || "$model_name" == *"Opus"* ]]; then
    if [ "$raw_effort" = "$default_effort" ]; then
      is_default=" ${DIM}(default)${RST}"
    fi
  fi
fi

model_part=""
if [ -n "$model_name" ]; then
  model_part="${BOLD}${MAGENTA}🤖 ${model_name}${RST} ${DIM}(${context_size})${RST}${is_default}"
fi

# ---------------------------------------------------------------------------
# Effort / thinking level
# ---------------------------------------------------------------------------
effort=""
raw_effort=$(echo "$input" | jq -r '.output_style.name // ""')
effort_level="$default_effort"
effort_suffix=" ${DIM}(default)${RST}"
if [ -n "$raw_effort" ] && [ "$raw_effort" != "$default_effort" ]; then
  effort_suffix=" ${DIM}(default, active: ${raw_effort})${RST}"
fi

case "$effort_level" in
  low)    effort="${DIM}🧠 low${RST}${effort_suffix}" ;;
  medium) effort="${YELLOW}🧠 medium${RST}${effort_suffix}" ;;
  high)   effort="${GREEN}🧠 high${RST}${effort_suffix}" ;;
  *)      effort="${CYAN}🧠 ${effort_level}${RST}${effort_suffix}" ;;
esac

# ---------------------------------------------------------------------------
# Git branch + diff stats
# ---------------------------------------------------------------------------
cwd=$(echo "$input" | jq -r '.cwd // ""')
git_part=""
if [ -n "$cwd" ]; then
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
  if [ -n "$branch" ]; then
    diff_stat=$(git -C "$cwd" diff --shortstat HEAD 2>/dev/null)
    insertions=0; deletions=0
    if [ -n "$diff_stat" ]; then
      ins=$(echo "$diff_stat" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+')
      del=$(echo "$diff_stat" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+')
      [ -n "$ins" ] && insertions=$ins
      [ -n "$del" ] && deletions=$del
    fi
    git_part="${BLUE}🌿 ${branch}${RST}"
    if [ "$insertions" -gt 0 ] || [ "$deletions" -gt 0 ]; then
      git_part+=" ${GREEN}+${insertions}${RST} ${RED}-${deletions}${RST}"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Cost
# ---------------------------------------------------------------------------
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
cost_part=""
if [ "$(echo "$cost > 0" | bc 2>/dev/null)" = "1" ]; then
  cost_part="${YELLOW}💰 \$$(printf '%.2f' "$cost")${RST}"
fi

# ---------------------------------------------------------------------------
# Token counters
# ---------------------------------------------------------------------------
total_in=$(echo "$input"  | jq -r '.context_window.total_input_tokens  // 0')
total_out=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
cached=$(echo "$input"    | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')

token_part="${CYAN}📥 $(fmt_tokens "$total_in")${RST}  ${GREEN}📤 $(fmt_tokens "$total_out")${RST}  ${DIM}📦 $(fmt_tokens "$cached")${RST}"

# ---------------------------------------------------------------------------
# Context window progress bar
# ---------------------------------------------------------------------------
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
used_pct=${used_pct:-0}

if [ "$used_pct" -ge 90 ] 2>/dev/null; then
  bar_color="$RED"
  pct_label="${RED}${BOLD}${used_pct}%${RST}"
elif [ "$used_pct" -ge 70 ] 2>/dev/null; then
  bar_color="$YELLOW"
  pct_label="${YELLOW}${used_pct}%${RST}"
else
  bar_color="$GREEN"
  pct_label="${GREEN}${used_pct}%${RST}"
fi

ctx_bar="$(progress_bar "$used_pct" 15 "$bar_color")"
context_part="📊 ${ctx_bar} ${pct_label}"

# ---------------------------------------------------------------------------
# Rate limits (5-hour block) — with caching to persist between updates
# ---------------------------------------------------------------------------
RATE_CACHE="/tmp/claude_rate_cache_${USER}.json"

# Try to get fresh rate limit data from input
rate_pct_fresh=$(echo "$input" | jq -r 'if .rate_limits.five_hour.used_percentage != null then .rate_limits.five_hour.used_percentage | tostring else "" end')
resets_at_fresh=$(echo "$input" | jq -r 'if .rate_limits.five_hour.resets_at != null then .rate_limits.five_hour.resets_at | tostring else "" end')

if [ -n "$rate_pct_fresh" ] && [ -n "$resets_at_fresh" ]; then
  # Fresh data available — write to cache
  echo "{\"rate_pct\": $rate_pct_fresh, \"resets_at\": $resets_at_fresh}" > "$RATE_CACHE"
  rate_pct="$rate_pct_fresh"
  resets_at="$resets_at_fresh"
elif [ -f "$RATE_CACHE" ]; then
  # No fresh data — fall back to cached values
  rate_pct=$(jq -r '.rate_pct // empty' "$RATE_CACHE" 2>/dev/null)
  resets_at=$(jq -r '.resets_at // empty' "$RATE_CACHE" 2>/dev/null)
fi

rate_part=""
if [ -n "$rate_pct" ]; then
  rate_int=$(printf '%.0f' "$rate_pct" 2>/dev/null || echo 0)

  if [ "$rate_int" -ge 80 ] 2>/dev/null; then
    rate_color="$RED"
  elif [ "$rate_int" -ge 50 ] 2>/dev/null; then
    rate_color="$YELLOW"
  else
    rate_color="$GREEN"
  fi

  rate_bar="$(progress_bar "$rate_int" 10 "$rate_color")"
  rate_label="${rate_color}${rate_int}%${RST}"

  # Time until reset — handle both Unix timestamp and ISO 8601
  reset_str=""
  if [ -n "$resets_at" ]; then
    # Normalize ISO 8601 to Unix timestamp if needed
    if [[ "$resets_at" == *"T"* ]]; then
      resets_at=$(date -d "$resets_at" +%s 2>/dev/null \
        || date -jf "%Y-%m-%dT%H:%M:%SZ" "$resets_at" +%s 2>/dev/null \
        || echo "")
    fi

    if [ -n "$resets_at" ]; then
      now=$(date +%s)
      diff=$((resets_at - now))
      if [ "$diff" -gt 0 ]; then
        hours=$((diff / 3600))
        mins=$(( (diff % 3600) / 60 ))
        reset_str=" ${DIM}(resets ${hours}h ${mins}m)${RST}"
      else
        # Cache has expired — delete it so stale data doesn't persist
        rm -f "$RATE_CACHE"
        reset_str=" ${DIM}(resetting...)${RST}"
      fi
    fi
  fi

  rate_part="⏱️  ${rate_bar} ${rate_label}${reset_str}"
fi

# ---------------------------------------------------------------------------
# Assemble lines
# ---------------------------------------------------------------------------
parts=()
[ -n "$model_part" ] && parts+=("$model_part")
[ -n "$effort"     ] && parts+=("$effort")
[ -n "$git_part"   ] && parts+=("$git_part")
[ -n "$cost_part"  ] && parts+=("$cost_part")

line1=""
for i in "${!parts[@]}"; do
  if [ "$i" -eq 0 ]; then
    line1="${parts[$i]}"
  else
    line1+="  ${DIM}│${RST}  ${parts[$i]}"
  fi
done

line2_parts=()
[ -n "$token_part" ] && line2_parts+=("$token_part")
line2_parts+=("$context_part")
[ -n "$rate_part"  ] && line2_parts+=("$rate_part")

line2=""
for i in "${!line2_parts[@]}"; do
  if [ "$i" -eq 0 ]; then
    line2="${line2_parts[$i]}"
  else
    line2+="  ${DIM}│${RST}  ${line2_parts[$i]}"
  fi
done

[ -n "$line1" ] && printf '%b\n' "$line1"
[ -n "$line2" ] && printf '%b\n' "$line2"