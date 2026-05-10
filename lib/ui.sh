#!/bin/sh

ui_init() {
  UI_WIDTH=${SEED_WIDTH:-${COLUMNS:-}}

  if [ -z "$UI_WIDTH" ]; then
    UI_WIDTH=$(stty size 2>/dev/null | sed 's/.* //')
  fi

  case "$UI_WIDTH" in
    ""|*[!0-9]*)
      UI_WIDTH=80
      ;;
  esac

  if [ "$UI_WIDTH" -lt 44 ]; then
    UI_WIDTH=44
  fi

  if [ "$UI_WIDTH" -gt 96 ]; then
    UI_WIDTH=96
  fi

  if { [ -t 1 ] || [ "${SEED_COLOR:-}" = "1" ]; } && [ "${TERM:-}" != "dumb" ] && [ -z "${NO_COLOR:-}" ]; then
    UI_RESET=$(printf '\033[0m')
    UI_BOLD=$(printf '\033[1m')
    UI_DIM=$(printf '\033[2m')
    UI_BLUE=$(printf '\033[34m')
    UI_GREEN=$(printf '\033[32m')
    UI_YELLOW=$(printf '\033[33m')
    UI_RED=$(printf '\033[31m')
  else
    UI_RESET=""
    UI_BOLD=""
    UI_DIM=""
    UI_BLUE=""
    UI_GREEN=""
    UI_YELLOW=""
    UI_RED=""
  fi

  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *UTF-8*|*utf8*|*utf-8*)
      UI_UTF=1
      ;;
    *)
      UI_UTF=0
      ;;
  esac

  if [ "${SEED_ASCII:-}" = "1" ] || [ "${TERM:-}" = "dumb" ]; then
    UI_UTF=0
  fi

  if [ "$UI_UTF" = "1" ]; then
    UI_TL="╭"; UI_TR="╮"; UI_BL="╰"; UI_BR="╯"
    UI_H="─"; UI_V="│"; UI_DOT="•"
  else
    UI_TL="+"; UI_TR="+"; UI_BL="+"; UI_BR="+"
    UI_H="-"; UI_V="|"; UI_DOT="-"
  fi
}

ui_repeat() {
  char=$1
  count=$2
  out=""

  while [ "$count" -gt 0 ]; do
    out=$out$char
    count=$((count - 1))
  done

  printf "%s" "$out"
}

ui_fit() {
  text=$1
  width=$2
  len=${#text}

  if [ "$len" -gt "$width" ]; then
    cut_width=$((width - 1))
    if [ "$UI_UTF" = "1" ]; then
      printf "%.${cut_width}s…" "$text"
    else
      printf "%.${cut_width}s." "$text"
    fi
  else
    printf "%-${width}s" "$text"
  fi
}

ui_header() {
  title=$1
  subtitle=${2:-lightweight system companion}
  inner=$((UI_WIDTH - 4))

  echo
  printf "%s%s%s%s%s\n" "$UI_BLUE" "$UI_TL" "$(ui_repeat "$UI_H" "$((UI_WIDTH - 2))")" "$UI_TR" "$UI_RESET"
  printf "%s%s%s %s%s%s %s%s\n" "$UI_BLUE" "$UI_V" "$UI_RESET" "$UI_BOLD" "$(ui_fit "$title" "$inner")" "$UI_RESET" "$UI_BLUE" "$UI_V"
  printf "%s%s%s %s%s %s%s\n" "$UI_BLUE" "$UI_V" "$UI_RESET" "$UI_DIM" "$(ui_fit "$subtitle" "$inner")" "$UI_BLUE" "$UI_V$UI_RESET"
  printf "%s%s%s%s%s\n" "$UI_BLUE" "$UI_BL" "$(ui_repeat "$UI_H" "$((UI_WIDTH - 2))")" "$UI_BR" "$UI_RESET"
}

ui_masthead() {
  title=$1
  subtitle=$2
  meta=${3:-}
  inner=$((UI_WIDTH - 2))

  echo
  printf " %s%s%s\n" "$UI_DIM" "$(ui_repeat "$UI_H" "$((UI_WIDTH / 4))")" "$UI_RESET"
  printf " %s%s%s\n" "$UI_BOLD" "$title" "$UI_RESET"
  printf " %s%s%s\n" "$UI_DIM" "$subtitle" "$UI_RESET"
  if [ -n "$meta" ]; then
    printf " %s%s%s\n" "$UI_DIM" "$(ui_fit "$meta" "$inner")" "$UI_RESET"
  fi
}

ui_focus() {
  label=$1
  value=$2
  note=${3:-}

  printf "\n%s%s%s\n" "$UI_DIM" "$label" "$UI_RESET"
  printf "%s%s%s\n" "$UI_BOLD" "$value" "$UI_RESET"
  if [ -n "$note" ]; then
    printf "%s%s%s\n" "$UI_DIM" "$note" "$UI_RESET"
  fi
}

ui_whisper() {
  printf "%s%s%s\n" "$UI_DIM" "$1" "$UI_RESET"
}

ui_separator() {
  label=$1
  label_len=${#label}
  rest=$((UI_WIDTH - label_len - 3))

  if [ "$rest" -lt 4 ]; then
    rest=4
  fi

  printf "\n%s%s%s %s %s\n" "$UI_BOLD" "$label" "$UI_RESET" "$UI_DIM" "$(ui_repeat "$UI_H" "$rest")$UI_RESET"
}

ui_section() {
  ui_separator "$1"
}

ui_line() {
  printf "  %s %s\n" "$UI_DOT" "$1"
}

ui_kv() {
  key=$1
  value=$2
  printf "  %s%-12s%s %s\n" "$UI_DIM" "$key:" "$UI_RESET" "$value"
}

ui_status() {
  label=$1
  status=$2
  note=${3:-}

  case "$status" in
    ok|present|ready)
      color=$UI_GREEN
      text="ready"
      ;;
    missing)
      color=$UI_YELLOW
      text="missing"
      ;;
    heavy)
      color=$UI_YELLOW
      text="optional"
      ;;
    later)
      color=$UI_DIM
      text="later"
      ;;
    *)
      color=$UI_DIM
      text=$status
      ;;
  esac

  printf "  %-14s %s%-10s%s %s%s%s\n" "$label" "$color" "$text" "$UI_RESET" "$UI_DIM" "$note" "$UI_RESET"
}

ui_prompt() {
  label=$1
  printf "%s%s%s " "$UI_YELLOW" "$label" "$UI_RESET"
}

ui_choice_bar() {
  if [ "$UI_WIDTH" -lt 66 ]; then
    printf "\n%s[ 1 ]%s full plan     %s[ 2 ]%s os details\n" "$UI_GREEN" "$UI_RESET" "$UI_GREEN" "$UI_RESET"
    printf "%s[ 3 ]%s modules       %s[ q ]%s quit\n" "$UI_GREEN" "$UI_RESET" "$UI_DIM" "$UI_RESET"
  else
    printf "\n%s[ 1 ]%s full plan   %s[ 2 ]%s os details   %s[ 3 ]%s modules   %s[ q ]%s quit\n" \
      "$UI_GREEN" "$UI_RESET" \
      "$UI_GREEN" "$UI_RESET" \
      "$UI_GREEN" "$UI_RESET" \
      "$UI_DIM" "$UI_RESET"
  fi
}

ui_card() {
  title=$1
  shift
  inner=$((UI_WIDTH - 4))

  printf "%s%s%s%s%s\n" "$UI_DIM" "$UI_TL" "$(ui_repeat "$UI_H" "$((UI_WIDTH - 2))")" "$UI_TR" "$UI_RESET"
  printf "%s%s%s %s%s%s %s%s\n" "$UI_DIM" "$UI_V" "$UI_RESET" "$UI_BOLD" "$(ui_fit "$title" "$inner")" "$UI_RESET" "$UI_DIM" "$UI_V$UI_RESET"
  while [ "$#" -gt 0 ]; do
    printf "%s%s%s %s %s%s\n" "$UI_DIM" "$UI_V" "$UI_RESET" "$(ui_fit "$1" "$inner")" "$UI_DIM" "$UI_V$UI_RESET"
    shift
  done
  printf "%s%s%s%s%s\n" "$UI_DIM" "$UI_BL" "$(ui_repeat "$UI_H" "$((UI_WIDTH - 2))")" "$UI_BR" "$UI_RESET"
}

ui_split_focus() {
  left_title=$1
  left_big=$2
  left_note=$3
  right_title=$4
  right_1=$5
  right_2=$6
  right_3=$7

  if [ "$UI_WIDTH" -lt 78 ]; then
    ui_focus "$left_title" "$left_big" "$left_note"
    echo
    ui_card "$right_title" "$right_1" "$right_2" "$right_3"
    return
  fi

  left_w=$((UI_WIDTH / 2 - 2))
  right_w=$((UI_WIDTH - left_w - 5))
  right_inner=$((right_w - 4))
  gap="     "

  printf "\n"
  printf "%s%-${left_w}s%s%s%s%s%s%s\n" "$UI_DIM" "$left_title" "$UI_RESET" "$gap" "$UI_DIM" "$UI_TL" "$(ui_repeat "$UI_H" "$((right_w - 2))")" "$UI_TR$UI_RESET"
  printf "%s%-${left_w}s%s%s%s%s%s %s%s%s %s%s\n" "$UI_BOLD" "$left_big" "$UI_RESET" "$gap" "$UI_DIM" "$UI_V" "$UI_RESET" "$UI_BOLD" "$(ui_fit "$right_title" "$right_inner")" "$UI_RESET" "$UI_DIM$UI_V$UI_RESET"
  printf "%s%-${left_w}s%s%s%s%s%s %s %s%s\n" "$UI_DIM" "$left_note" "$UI_RESET" "$gap" "$UI_DIM" "$UI_V" "$UI_RESET" "$(ui_fit "$right_1" "$right_inner")" "$UI_DIM$UI_V$UI_RESET"
  printf "%-${left_w}s%s%s%s%s %s %s%s\n" "" "$gap" "$UI_DIM" "$UI_V" "$UI_RESET" "$(ui_fit "$right_2" "$right_inner")" "$UI_DIM$UI_V$UI_RESET"
  printf "%-${left_w}s%s%s%s%s %s %s%s\n" "" "$gap" "$UI_DIM" "$UI_V" "$UI_RESET" "$(ui_fit "$right_3" "$right_inner")" "$UI_DIM$UI_V$UI_RESET"
  printf "%-${left_w}s%s%s%s%s%s%s\n" "" "$gap" "$UI_DIM" "$UI_BL" "$(ui_repeat "$UI_H" "$((right_w - 2))")" "$UI_BR" "$UI_RESET"
}

ui_card_pair() {
  left_title=$1
  left_1=$2
  left_2=$3
  left_3=$4
  right_title=$5
  right_1=$6
  right_2=$7
  right_3=$8

  if [ "$UI_WIDTH" -lt 86 ]; then
    ui_card "$left_title" "$left_1" "$left_2" "$left_3"
    echo
    ui_card "$right_title" "$right_1" "$right_2" "$right_3"
    return
  fi

  card_w=$(((UI_WIDTH - 3) / 2))
  inner=$((card_w - 4))
  gap="   "

  printf "%s%s%s%s%s%s%s%s%s%s\n" "$UI_DIM" "$UI_TL" "$(ui_repeat "$UI_H" "$((card_w - 2))")" "$UI_TR" "$UI_RESET" "$gap" "$UI_DIM" "$UI_TL" "$(ui_repeat "$UI_H" "$((card_w - 2))")" "$UI_TR$UI_RESET"
  printf "%s%s%s %s%s%s %s%s%s%s%s%s %s%s%s %s%s\n" "$UI_DIM" "$UI_V" "$UI_RESET" "$UI_BOLD" "$(ui_fit "$left_title" "$inner")" "$UI_RESET" "$UI_DIM" "$UI_V" "$UI_RESET" "$gap" "$UI_DIM" "$UI_V" "$UI_RESET" "$UI_BOLD" "$(ui_fit "$right_title" "$inner")" "$UI_RESET" "$UI_DIM$UI_V$UI_RESET"
  printf "%s%s%s %s %s%s%s%s%s%s %s %s%s\n" "$UI_DIM" "$UI_V" "$UI_RESET" "$(ui_fit "$left_1" "$inner")" "$UI_DIM" "$UI_V" "$UI_RESET" "$gap" "$UI_DIM" "$UI_V" "$UI_RESET" "$(ui_fit "$right_1" "$inner")" "$UI_DIM$UI_V$UI_RESET"
  printf "%s%s%s %s %s%s%s%s%s%s %s %s%s\n" "$UI_DIM" "$UI_V" "$UI_RESET" "$(ui_fit "$left_2" "$inner")" "$UI_DIM" "$UI_V" "$UI_RESET" "$gap" "$UI_DIM" "$UI_V" "$UI_RESET" "$(ui_fit "$right_2" "$inner")" "$UI_DIM$UI_V$UI_RESET"
  printf "%s%s%s %s %s%s%s%s%s%s %s %s%s\n" "$UI_DIM" "$UI_V" "$UI_RESET" "$(ui_fit "$left_3" "$inner")" "$UI_DIM" "$UI_V" "$UI_RESET" "$gap" "$UI_DIM" "$UI_V" "$UI_RESET" "$(ui_fit "$right_3" "$inner")" "$UI_DIM$UI_V$UI_RESET"
  printf "%s%s%s%s%s%s%s%s%s%s\n" "$UI_DIM" "$UI_BL" "$(ui_repeat "$UI_H" "$((card_w - 2))")" "$UI_BR" "$UI_RESET" "$gap" "$UI_DIM" "$UI_BL" "$(ui_repeat "$UI_H" "$((card_w - 2))")" "$UI_BR$UI_RESET"
}

ui_pause() {
  echo
  ui_prompt "press enter to continue..."
  IFS= read -r _ || true
}

ui_init
