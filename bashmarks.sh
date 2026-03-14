#!/bin/bash
# Bashmarks is a simple set of bash and zsh functions that allows you to
# bookmark folders in the command-line.
#
# To install, put bashmarks.sh somewhere such as ~/bin, then source it
# in your .bashrc or .zshrc file:
#   source ~/bin/bashmarks.sh
#
# To bookmark a folder, simply go to that folder, then bookmark it like so:
#   bookmark foo
#
# The bookmark will be named "foo"
#
# When you want to get back to that folder use:
#   cdd foo
#
# To see a list of bookmarks:
#   cdd ?
#
# Tab completion works, to go to the shoobie bookmark:
#   cdd sho[tab]
#
# Your bookmarks are stored in the file specified in the $BASHMARKS_FILE
# environment variable (Default: ~/.bashmarks)

__bm_bookmarks_file() {
    local bookmarks_file=${BASHMARKS_FILE:-"$HOME/.bashmarks"}

    # Create bookmarks_file if it doesn't exist
    [[ -f $bookmarks_file ]] || touch "$bookmarks_file"
    echo "$bookmarks_file"
}

# Resolve a bookmark path: expand variables, then treat relative paths as
# relative to $HOME.
__bm_resolve_path() {
    local bm_path="$1"
    bm_path=$(eval "echo \"$bm_path\"" 2>/dev/null) || return 1
    [[ $bm_path == /* ]] || bm_path="$HOME/$bm_path"
    echo "$bm_path"
}

# Shorten a path for display: replace $HOME prefix with ~
__bm_display_path() {
    local p="$1"
    if [[ $p == "$HOME"/* ]]; then
        echo "~${p#"$HOME"}"
    elif [[ $p == "$HOME" ]]; then
        echo "~"
    else
        echo "$p"
    fi
}

__bm_resolve_includes() {
    local bookmarks_file
    bookmarks_file=$(__bm_bookmarks_file)
    local resolved_main
    resolved_main=$(command realpath "$bookmarks_file")

    while read -r line; do
        local inc_path="${line#\#include }"
        # Expand ~ and variables
        inc_path=$(eval echo "$inc_path" 2>/dev/null) || continue
        # Resolve relative paths against the bookmarks file's directory
        [[ $inc_path == /* ]] || inc_path="$(dirname "$bookmarks_file")/$inc_path"
        # Skip empty paths, missing files, and self-includes
        [[ -n $inc_path ]] || continue
        [[ -f $inc_path ]] || continue
        local resolved_inc
        resolved_inc=$(command realpath "$inc_path")
        [[ $resolved_inc != "$resolved_main" ]] || continue

        echo "$inc_path"
    done < <(grep '^#include ' "$bookmarks_file")
}

__bm_all_bookmarks() {
    local bookmarks_file
    bookmarks_file=$(__bm_bookmarks_file)

    # Output bookmark lines from the main file (skip comments and blanks)
    grep -v '^#\|^$' "$bookmarks_file" || true

    # Output bookmark lines from each included file
    local inc_file
    while read -r inc_file; do
        grep -v '^#\|^$' "$inc_file" || true
    done < <(__bm_resolve_includes)
}

__bm_check() {
    local bookmarks_file
    bookmarks_file=$(__bm_bookmarks_file)
    local errors=0
    local total_entries=0
    local -A seen_names

    # Validate a single bookmarks file. Updates seen_names, errors, and total_entries.
    # Usage: __bm_check_file <filepath> <label>
    __bm_check_file() {
        local file="$1"
        local label="$2"

        while IFS=: read -r line_num line; do
            # Check line format: should have exactly one |
            local pipe_count
            pipe_count=$(echo "$line" | tr -cd '|' | wc -c)
            if [[ $pipe_count -ne 1 ]]; then
                echo "$label:$line_num: Invalid format (expected 'path|name'): $line"
                ((errors++))
                continue
            fi

            local name
            name=$(echo "$line" | cut -d'|' -f2)

            # Check name is not empty
            if [[ -z $name ]]; then
                echo "$label:$line_num: Empty bookmark name: $line"
                ((errors++))
                continue
            fi

            ((total_entries++))

            # Check for duplicate names across all files
            if [[ -n ${seen_names[$name]+x} ]]; then
                echo "$label:$line_num: Duplicate bookmark name '$name' (first seen at ${seen_names[$name]})"
                ((errors++))
            else
                seen_names[$name]="$label:$line_num"
            fi
        done < <(grep -n -v '^#\|^$' "$file" || true)
    }

    # Validate main bookmarks file
    __bm_check_file "$bookmarks_file" "$bookmarks_file"

    # Check #include directives
    local bookmarks_dir
    bookmarks_dir=$(dirname "$bookmarks_file")
    local line_num=0
    while read -r line; do
        ((line_num++))
        [[ $line == '#include '* ]] || continue

        local inc_path="${line#\#include }"
        inc_path=$(eval echo "$inc_path" 2>/dev/null) || continue
        # Resolve relative paths against the bookmarks file's directory
        [[ $inc_path == /* ]] || inc_path="$bookmarks_dir/$inc_path"

        if [[ -z $inc_path ]]; then
            continue
        fi

        if [[ ! -f $inc_path ]]; then
            echo "$bookmarks_file:$line_num: Warning: included file not found: $inc_path"
            continue
        fi

        # Validate included file
        __bm_check_file "$inc_path" "$inc_path"
    done <"$bookmarks_file"

    unset -f __bm_check_file

    if [[ $errors -eq 0 ]]; then
        echo "Bookmarks OK ($total_entries entries)"
        return 0
    else
        echo
        echo "Found $errors error(s) ($total_entries entries)"
        return 1
    fi
}

__bm_show() {
    while IFS='|' read -r bm_path name; do
        bm_path=$(__bm_resolve_path "$bm_path") || continue
        printf "%-10s %-40s\n" "$name" "$(__bm_display_path "$bm_path")"
    done < <(__bm_all_bookmarks)
}

bookmark() {
    local bookmark_name="$1"
    local bookmarks_file
    bookmarks_file=$(__bm_bookmarks_file)

    if [[ -z $bookmark_name ]] || [[ $bookmark_name = '?' ]]; then
        echo 'Invalid name, please provide a name for your bookmark. For example:'
        echo '    bookmark foo'
        return 1
    else
        local bookmark
        bookmark="$(pwd)|$bookmark_name" # Store the bookmark as folder|name

        # Check for duplicate by name only (across all files)
        local existing
        existing=$(__bm_all_bookmarks | grep "|$bookmark_name$")
        if [[ -n $existing ]]; then
            local existing_path
            existing_path=$(echo "$existing" | cut -d'|' -f1)
            existing_path=$(__bm_resolve_path "$existing_path")
            echo "Error: Bookmark '$bookmark_name' already exists:"
            echo "  $existing_path"
            return 1
        else
            echo "$bookmark" >>"$bookmarks_file"
            echo "Bookmark '$bookmark_name' saved"
        fi
    fi
}

cdd() {
    local bookmark_name="$1"
    local bookmarks_file
    bookmarks_file=$(__bm_bookmarks_file)

    [[ $bookmark_name == '?' ]] && __bm_show && return 0
    [[ $bookmark_name == '-c' || $bookmark_name == '--check' ]] && {
        __bm_check
        return $?
    }
    [[ $bookmark_name == '-e' || $bookmark_name == '--edit' ]] && {
        ${EDITOR:-vi} "$bookmarks_file"
        return 0
    }

    local bookmark
    bookmark=$(__bm_all_bookmarks | grep "|$bookmark_name$" | head -1)

    if [[ -z $bookmark ]]; then
        echo 'Invalid name, please provide a valid bookmark name. For example:'
        echo '  cdd foo'
        echo
        echo "To bookmark a folder, go to the folder then do this (naming the bookmark 'foo'):"
        echo '  bookmark foo'
        return 1
    else
        local dir
        dir=$(__bm_resolve_path "$(echo "$bookmark" | cut -d'|' -f1)")
        cd "$dir" || return
    fi
}

# --- Shell-specific tab completion ---

if type compdef >/dev/null 2>&1; then
    # Zsh: use _describe for native name+description completion
    _complete_bashmarks() {
        local -a entries
        while IFS='|' read -r bm_path name; do
            bm_path=$(__bm_resolve_path "$bm_path") || continue
            entries+=("${name}:$(__bm_display_path "$bm_path")")
        done < <(__bm_all_bookmarks)
        _describe 'bookmark' entries
    }
    compdef _complete_bashmarks cdd

elif type complete >/dev/null 2>&1; then
    # Bash: Docker-style completion with path shown in parentheses
    __complete_bashmarks() {
        local cur="${COMP_WORDS[COMP_CWORD]}"
        local -a names paths

        while IFS='|' read -r bm_path name; do
            [[ $name == "$cur"* ]] || continue
            bm_path=$(__bm_resolve_path "$bm_path") || continue
            names+=("$name")
            paths+=("$bm_path")
        done < <(__bm_all_bookmarks)

        if [[ ${#names[@]} -eq 0 ]]; then
            return
        elif [[ ${#names[@]} -eq 1 ]]; then
            COMPREPLY=("${names[0]}")
        else
            # Multiple matches: show name + path description
            local max_len=0
            for n in "${names[@]}"; do
                ((${#n} > max_len)) && max_len=${#n}
            done
            COMPREPLY=()
            for i in "${!names[@]}"; do
                printf -v entry "%-${max_len}s  (%s)" "${names[$i]}" "$(__bm_display_path "${paths[$i]}")"
                COMPREPLY+=("$entry")
            done
        fi
    }
    complete -F __complete_bashmarks -o default cdd
fi
