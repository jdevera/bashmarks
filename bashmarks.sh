#!/bin/bash
# Bashmarks is a simple set of bash functions that allows you to bookmark
# folders in the command-line.
#
# To install, put bashmarks.sh somewhere such as ~/bin, then source it
# in your .bashrc file (or other bash startup file):
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
    local bookmarks_file=${BASHMARKS_FILE:-~/.bashmarks}

    # Create bookmarks_file if it doesn't exist
    [[ -f $bookmarks_file ]] || touch "$bookmarks_file"
    echo "$bookmarks_file"
}

__bm_resolve_includes() {
    local bookmarks_file
    bookmarks_file=$(__bm_bookmarks_file)
    local resolved_main
    resolved_main=$(cd -P "$(dirname "$bookmarks_file")" && echo "$(pwd)/$(basename "$bookmarks_file")")

    grep '^#include ' "$bookmarks_file" | while read -r line; do
        local path="${line#\#include }"
        # Expand ~ and variables
        path=$(eval echo "$path" 2>/dev/null) || continue
        # Skip empty paths, missing files, and self-includes
        [[ -n $path ]] || continue
        [[ -f $path ]] || continue
        local resolved_path
        resolved_path=$(cd -P "$(dirname "$path")" && echo "$(pwd)/$(basename "$path")")
        [[ $resolved_path != "$resolved_main" ]] || continue

        echo "$path"
    done
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
    local line_num=0
    while read -r line; do
        ((line_num++))
        [[ $line == '#include '* ]] || continue

        local path="${line#\#include }"
        path=$(eval echo "$path" 2>/dev/null) || continue

        if [[ -z $path ]]; then
            continue
        fi

        if [[ ! -f $path ]]; then
            echo "$bookmarks_file:$line_num: Warning: included file not found: $path"
            continue
        fi

        # Validate included file
        __bm_check_file "$path" "$path"
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
    while read -r line; do
        bookmark=$(eval "echo \"$line\"")
        echo "$bookmark" | awk '{ printf "%-10s %-40s\n",$2,$1}' FS=\|
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
            existing_path=$(eval "echo \"$existing_path\"")
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
        dir=$(eval "echo $(echo "$bookmark" | cut -d\| -f1)")
        cd "$dir" || return
    fi
}

__complete_bashmarks() {
    # Get a list of bookmark names, then grep for what was entered to narrow the list
    __bm_all_bookmarks | cut -d\| -f2 | grep "^$2.*"
}

complete -C __complete_bashmarks -o default cdd
