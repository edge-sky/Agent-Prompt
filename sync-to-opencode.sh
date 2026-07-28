#!/usr/bin/env bash

# Copy the repository's OpenCode agents, skills, and plugins into a global
# OpenCode configuration directory. This script intentionally avoids GNU-only
# utilities so it can run with the Bash version shipped by macOS.

set -u

PROGRAM_NAME=${0##*/}

print_usage() {
  printf '%s\n' \
    "Usage:" \
    "  $PROGRAM_NAME [--target-dir /absolute/path] [--all|--agents|--skills|--plugins]" \
    "" \
    "Options:" \
    "  --all          Sync agents, skills, and plugins." \
    "  --agents       Sync top-level agents/*.md files." \
    "  --skills       Sync the complete skills directory tree." \
    "  --plugins      Sync the complete plugins directory tree." \
    "  --target-dir   Override the global OpenCode config directory." \
    "  -h, --help     Show this help message." \
    "" \
    "The category options may be combined. If none is supplied, an interactive" \
    "menu is shown. Existing destination files are confirmed one at a time." \
    "When agents are selected, available models are shown before three optional" \
    "model-tier prompts. Blank model input skips configuration for that tier."
}

print_error() {
  printf 'Error: %s\n' "$*" >&2
}

resolve_script_root() {
  local script_dir

  script_dir=$(dirname -- "$0") || return 1
  CDPATH= cd -P -- "$script_dir" 2>/dev/null || return 1
  pwd -P
}

SOURCE_ROOT=$(resolve_script_root) || {
  print_error "Unable to resolve the repository root from the script location."
  exit 1
}

target_root=''
sync_agents=0
sync_skills=0
sync_plugins=0
selection_supplied=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target-dir)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then
        print_error "--target-dir requires an absolute directory path."
        print_usage >&2
        exit 2
      fi
      case "$2" in
        /*) ;;
        *)
          print_error "The target directory must be absolute: $2"
          exit 2
          ;;
      esac
      target_root=$2
      shift 2
      ;;
    --all)
      sync_agents=1
      sync_skills=1
      sync_plugins=1
      selection_supplied=1
      shift
      ;;
    --agents)
      sync_agents=1
      selection_supplied=1
      shift
      ;;
    --skills)
      sync_skills=1
      selection_supplied=1
      shift
      ;;
    --plugins)
      sync_plugins=1
      selection_supplied=1
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      print_error "Unknown argument: $1"
      print_usage >&2
      exit 2
      ;;
  esac
done

if [ "$selection_supplied" -eq 0 ]; then
  while :; do
    printf '%s\n' \
      "Select what to sync:" \
      "  1) all" \
      "  2) agents" \
      "  3) skills" \
      "  4) plugins"
    printf 'Selection [1-4]: '

    selection=''
    if ! IFS= read -r selection; then
      printf '\n' >&2
      print_error "No sync selection was provided."
      exit 2
    fi

    case "$selection" in
      1|all)
        sync_agents=1
        sync_skills=1
        sync_plugins=1
        break
        ;;
      2|agents)
        sync_agents=1
        break
        ;;
      3|skills)
        sync_skills=1
        break
        ;;
      4|plugins)
        sync_plugins=1
        break
        ;;
      *)
        printf 'Invalid selection: %s\n\n' "$selection" >&2
        ;;
    esac
  done
fi

if [ -z "$target_root" ]; then
  if [ -n "${XDG_CONFIG_HOME:-}" ]; then
    target_root=$XDG_CONFIG_HOME/opencode
  elif [ -n "${HOME:-}" ]; then
    target_root=$HOME/.config/opencode
  else
    print_error "Neither XDG_CONFIG_HOME nor HOME is set; use --target-dir."
    exit 2
  fi
fi

case "$target_root" in
  /*) ;;
  *)
    print_error "The target directory must be absolute: $target_root"
    exit 2
    ;;
esac

if ! mkdir -p -- "$target_root"; then
  print_error "Unable to create the target directory: $target_root"
  exit 1
fi

TARGET_ROOT=$(CDPATH= cd -P -- "$target_root" 2>/dev/null && pwd -P) || {
  print_error "Unable to resolve the target directory: $target_root"
  exit 1
}

added_count=0
overwritten_count=0
skipped_count=0
missing_count=0
failed_count=0
available_models=''
tier_one_model=''
tier_two_model=''
tier_three_model=''
prompted_model=''

discover_available_models() {
  local model_output

  if ! command -v opencode >/dev/null 2>&1; then
    return
  fi

  model_output=$(OPENCODE_CONFIG_DIR="$TARGET_ROOT" opencode models --pure 2>/dev/null) || return
  available_models=$(printf '%s\n' "$model_output" |
    awk '/^[^[:space:]\/]+\/[^[:space:]]+$/ { print }' |
    LC_ALL=C sort -u)
}

model_is_available() {
  local candidate=$1

  printf '%s\n' "$available_models" | grep -Fqx -- "$candidate"
}

prompt_for_tier_model() {
  local tier_label=$1
  local agent_names=$2
  local answer=''
  local model_part=''
  local provider_part=''

  prompted_model=''
  while :; do
    printf '\n%s模型（%s，输入完整 provider/model，留空跳过）: ' "$tier_label" "$agent_names"
    if ! IFS= read -r answer; then
      printf '\n'
      answer=''
    fi

    if [ -z "$answer" ]; then
      return
    fi

    case "$answer" in
      *[[:space:]]*)
        printf '模型 ID 不能包含空白字符。\n' >&2
        continue
        ;;
      */*)
        provider_part=${answer%%/*}
        model_part=${answer#*/}
        if [ -z "$provider_part" ] || [ -z "$model_part" ]; then
          printf '模型 ID 必须使用非空的 provider/model 格式。\n' >&2
          continue
        fi
        ;;
      *)
        printf '模型 ID 必须使用 provider/model 格式。\n' >&2
        continue
        ;;
    esac

    if [ -n "$available_models" ] && ! model_is_available "$answer"; then
      printf '未识别该模型，请输入上方列表中的完整 provider/model，或留空跳过。\n' >&2
      continue
    fi

    prompted_model=$answer
    return
  done
}

configure_agent_models() {
  discover_available_models

  printf '\n模型等级说明：一级是能力最强的模型，向后依次递减。\n'
  if [ -n "$available_models" ]; then
    printf '已识别的提供商/模型：\n'
    while IFS= read -r model_id; do
      printf '  %s\n' "$model_id"
    done <<EOF
$available_models
EOF
  else
    printf '未能从 OpenCode 识别提供商/模型；仍可手动输入 provider/model。\n'
  fi

  prompt_for_tier_model '一级' 'Fish、Reviewer'
  tier_one_model=$prompted_model
  prompt_for_tier_model '二级' 'Analyst、Explore、Worker 及其他 Agent'
  tier_two_model=$prompted_model
  prompt_for_tier_model '三级' 'Sync、plan-init'
  tier_three_model=$prompted_model
}

render_agent_with_model() {
  local source_path=$1
  local output_path=$2
  local model=$3

  OPENCODE_AGENT_MODEL=$model awk '
    BEGIN {
      model_line = "model: " ENVIRON["OPENCODE_AGENT_MODEL"]
    }
    NR == 1 {
      if ($0 != "---") {
        exit 2
      }
      in_frontmatter = 1
      print
      next
    }
    in_frontmatter && $0 == "---" {
      if (!model_written) {
        print model_line
      }
      print
      frontmatter_closed = 1
      in_frontmatter = 0
      next
    }
    in_frontmatter && $0 ~ /^model[[:space:]]*:/ {
      if (!model_written) {
        print model_line
        model_written = 1
      }
      next
    }
    {
      print
    }
    END {
      if (!frontmatter_closed) {
        exit 3
      }
    }
  ' "$source_path" > "$output_path"
}

copy_regular_file() {
  local source_path=$1
  local destination_path=$2
  local model=${3-}
  local destination_parent
  local rendered_path=''
  local temporary_path

  destination_parent=${destination_path%/*}
  temporary_path=$(mktemp "$destination_parent/.opencode-sync.XXXXXX") || return 1

  if ! cp -p -- "$source_path" "$temporary_path"; then
    rm -f -- "$temporary_path"
    return 1
  fi

  if [ -n "$model" ]; then
    rendered_path=$(mktemp "$destination_parent/.opencode-sync.XXXXXX") || {
      rm -f -- "$temporary_path"
      return 1
    }
    if ! render_agent_with_model "$source_path" "$rendered_path" "$model"; then
      rm -f -- "$temporary_path" "$rendered_path"
      return 2
    fi
    if ! cat "$rendered_path" > "$temporary_path"; then
      rm -f -- "$temporary_path" "$rendered_path"
      return 1
    fi
    rm -f -- "$rendered_path"
  fi

  # A portable mv may follow a destination symlink that points to a directory.
  # Remove the confirmed destination link only after the replacement is ready.
  if [ -L "$destination_path" ] && ! rm -f -- "$destination_path"; then
    rm -f -- "$temporary_path"
    return 1
  fi

  if ! mv -f -- "$temporary_path" "$destination_path"; then
    rm -f -- "$temporary_path"
    return 1
  fi
}

copy_symbolic_link() {
  local source_path=$1
  local destination_path=$2
  local destination_parent
  local link_target
  local temporary_dir
  local temporary_link

  destination_parent=${destination_path%/*}
  link_target=$(readlink "$source_path") || return 1
  temporary_dir=$(mktemp -d "$destination_parent/.opencode-sync.XXXXXX") || return 1
  temporary_link=$temporary_dir/item

  if ! ln -s "$link_target" "$temporary_link"; then
    rmdir "$temporary_dir" 2>/dev/null || true
    return 1
  fi

  if [ -L "$destination_path" ] && ! rm -f -- "$destination_path"; then
    rm -f -- "$temporary_link"
    rmdir "$temporary_dir" 2>/dev/null || true
    return 1
  fi

  if ! mv -f -- "$temporary_link" "$destination_path"; then
    rm -f -- "$temporary_link"
    rmdir "$temporary_dir" 2>/dev/null || true
    return 1
  fi

  rmdir "$temporary_dir" 2>/dev/null || true
}

copy_one_file() {
  local source_path=$1
  local destination_path=$2
  local model=${3-}
  local existed=0
  local answer=''
  local copy_status=0

  if ! mkdir -p -- "${destination_path%/*}"; then
    print_error "Unable to create the destination directory for: $destination_path"
    failed_count=$((failed_count + 1))
    return
  fi

  if [ -d "$destination_path" ] && [ ! -L "$destination_path" ]; then
    print_error "A directory blocks the destination file: $destination_path"
    failed_count=$((failed_count + 1))
    return
  fi

  if [ -e "$destination_path" ] || [ -L "$destination_path" ]; then
    existed=1
    printf 'Destination exists: %s\n' "$destination_path"
    printf '是否覆盖此文件？ [y/N]: '
    if ! IFS= read -r answer; then
      printf '\n'
      answer=''
    fi

    case "$answer" in
      y|Y) ;;
      *)
        printf 'Skipped: %s\n' "$destination_path"
        skipped_count=$((skipped_count + 1))
        return
        ;;
    esac
  fi

  if [ -L "$source_path" ] && [ -n "$model" ]; then
    print_error "Cannot inject a model into a symbolic-link Agent file: $source_path"
    failed_count=$((failed_count + 1))
    return
  elif [ -L "$source_path" ]; then
    if ! copy_symbolic_link "$source_path" "$destination_path"; then
      print_error "Unable to copy symbolic link: $source_path"
      failed_count=$((failed_count + 1))
      return
    fi
  elif [ -f "$source_path" ]; then
    copy_regular_file "$source_path" "$destination_path" "$model" || copy_status=$?
    if [ "$copy_status" -ne 0 ]; then
      if [ "$copy_status" -eq 2 ]; then
        print_error "Unable to set the model because Agent frontmatter is invalid: $source_path"
      else
        print_error "Unable to copy file: $source_path"
      fi
      failed_count=$((failed_count + 1))
      return
    fi
  else
    print_error "Unsupported source file type: $source_path"
    failed_count=$((failed_count + 1))
    return
  fi

  if [ "$existed" -eq 1 ]; then
    overwritten_count=$((overwritten_count + 1))
    printf 'Overwritten: %s\n' "$destination_path"
  else
    added_count=$((added_count + 1))
    printf 'Added: %s\n' "$destination_path"
  fi
}

sync_agent_files() {
  local source_dir=$SOURCE_ROOT/agents
  local destination_dir=$TARGET_ROOT/agents
  local assigned_model=''
  local source_path
  local found=0

  if [ ! -d "$source_dir" ]; then
    printf 'Source directory is missing; skipped: %s\n' "$source_dir"
    missing_count=$((missing_count + 1))
    return
  fi

  if ! mkdir -p -- "$destination_dir"; then
    print_error "Unable to create the destination directory: $destination_dir"
    failed_count=$((failed_count + 1))
    return
  fi

  for source_path in "$source_dir"/*.md; do
    if [ ! -f "$source_path" ] && [ ! -L "$source_path" ]; then
      continue
    fi
    found=1
    break
  done

  if [ "$found" -eq 0 ]; then
    printf 'No top-level Agent markdown files found: %s\n' "$source_dir"
    return
  fi

  configure_agent_models

  for source_path in "$source_dir"/*.md; do
    if [ ! -f "$source_path" ] && [ ! -L "$source_path" ]; then
      continue
    fi

    case "${source_path##*/}" in
      Fish.md|Reviewer.md)
        assigned_model=$tier_one_model
        ;;
      Sync.md|plan-init.md)
        assigned_model=$tier_three_model
        ;;
      *)
        assigned_model=$tier_two_model
        ;;
    esac

    copy_one_file "$source_path" "$destination_dir/${source_path##*/}" "$assigned_model"
  done
}

sync_directory_tree() {
  local category=$1
  local source_dir=$SOURCE_ROOT/$category
  local destination_dir=$TARGET_ROOT/$category
  local source_path
  local relative_path

  if [ ! -d "$source_dir" ]; then
    printf 'Source directory is missing; skipped: %s\n' "$source_dir"
    missing_count=$((missing_count + 1))
    return
  fi

  if ! mkdir -p -- "$destination_dir"; then
    print_error "Unable to create the destination directory: $destination_dir"
    failed_count=$((failed_count + 1))
    return
  fi

  while IFS= read -r -d '' source_path; do
    if [ "$source_path" = "$source_dir" ]; then
      continue
    fi
    relative_path=${source_path#"$source_dir"/}
    if ! mkdir -p -- "$destination_dir/$relative_path"; then
      print_error "Unable to create destination directory: $destination_dir/$relative_path"
      failed_count=$((failed_count + 1))
    fi
  done < <(find "$source_dir" -type d -print0)

  while IFS= read -r -d '' source_path; do
    relative_path=${source_path#"$source_dir"/}
    copy_one_file "$source_path" "$destination_dir/$relative_path"
  done < <(find "$source_dir" \( -type f -o -type l \) -print0)
}

printf 'Repository: %s\n' "$SOURCE_ROOT"
printf 'Target:     %s\n' "$TARGET_ROOT"

if [ "$sync_agents" -eq 1 ]; then
  sync_agent_files
fi
if [ "$sync_skills" -eq 1 ]; then
  sync_directory_tree skills
fi
if [ "$sync_plugins" -eq 1 ]; then
  sync_directory_tree plugins
fi

printf '\nSummary\n'
printf '  Added:              %d\n' "$added_count"
printf '  Overwritten:        %d\n' "$overwritten_count"
printf '  Skipped:            %d\n' "$skipped_count"
printf '  Missing directories: %d\n' "$missing_count"
printf '  Failed:             %d\n' "$failed_count"

if [ "$failed_count" -gt 0 ]; then
  exit 1
fi
