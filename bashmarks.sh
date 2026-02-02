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

__bm_bookmarks_file(){
    local bookmarks_file=${BASHMARKS_FILE:-~/.bashmarks}

    # Create bookmarks_file if it doesn't exist
    [[ -f $bookmarks_file ]] || touch "$bookmarks_file"
    echo "$bookmarks_file"
}

__bm_check()
{
    local bookmarks_file
    bookmarks_file=$(__bm_bookmarks_file)
    local line_num=0
    local errors=0
    local -A seen_names

    while read -r line; do
        ((line_num++))

        # Skip empty lines
        [[ -z $line ]] && continue

        # Check line format: should have exactly one |
        local pipe_count
        pipe_count=$(echo "$line" | tr -cd '|' | wc -c)
        if [[ $pipe_count -ne 1 ]]; then
            echo "Line $line_num: Invalid format (expected 'path|name'): $line"
            ((errors++))
            continue
        fi

        local name
        name=$(echo "$line" | cut -d'|' -f2)

        # Check name is not empty
        if [[ -z $name ]]; then
            echo "Line $line_num: Empty bookmark name: $line"
            ((errors++))
            continue
        fi

        # Check for duplicate names
        if [[ -n ${seen_names[$name]+x} ]]; then
            echo "Line $line_num: Duplicate bookmark name '$name' (first seen on line ${seen_names[$name]})"
            ((errors++))
        else
            seen_names[$name]=$line_num
        fi
    done < "$bookmarks_file"

    if [[ $errors -eq 0 ]]; then
        echo "Bookmarks file OK ($(wc -l < "$bookmarks_file" | tr -d ' ') entries)"
        return 0
    else
        echo
        echo "Found $errors error(s)"
        return 1
    fi
}

__bm_show()
{
    local bookmarks_file
    bookmarks_file=$(__bm_bookmarks_file)
    while read -r line
    do
        bookmark=$(eval "echo \"$line\"")
        echo "$bookmark" | awk '{ printf "%-10s %-40s\n",$2,$1}' FS=\|
    done < "$bookmarks_file"

}

bookmark (){
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

        # Check for duplicate by name only
        local existing
        existing=$(grep "|$bookmark_name$" "$bookmarks_file")
        if [[ -n $existing ]]; then
            local existing_path
            existing_path=$(echo "$existing" | cut -d'|' -f1)
            existing_path=$(eval "echo \"$existing_path\"")
            echo "Error: Bookmark '$bookmark_name' already exists:"
            echo "  $existing_path"
            return 1
        else
            echo "$bookmark" >> "$bookmarks_file"
            echo "Bookmark '$bookmark_name' saved"
        fi
    fi
} 

cdd(){
  local bookmark_name="$1"
  local bookmarks_file
  bookmarks_file=$(__bm_bookmarks_file)

  [[ $bookmark_name == '?'  ]] && __bm_show && return 0;
  [[ $bookmark_name == '-c' || $bookmark_name == '--check' ]] && { __bm_check; return $?; }
  [[ $bookmark_name == '-e' || $bookmark_name == '--edit' ]] && { ${EDITOR:-vi} "$bookmarks_file" ; return 0; }

  local bookmark
  bookmark=$( grep "|$bookmark_name$" "$bookmarks_file" )

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

__complete_bashmarks(){
  # Get a list of bookmark names, then grep for what was entered to narrow the list
  local bookmarks_file
  bookmarks_file=$(__bm_bookmarks_file)
  cut -d\| -f2 < "$bookmarks_file" | grep "^$2.*"
}

complete -C __complete_bashmarks -o default cdd
