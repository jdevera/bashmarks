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
#   go foo
#
# To see a list of bookmarks:
#   bookmarksshow
# 
# Tab completion works, to go to the shoobie bookmark:
#   go sho[tab]
# 
# Your bookmarks are stored in the file specified in the $BASHMARKS_FILE
# environment variable (Default: ~/.bookmarks)

bookmarks_file(){
    local bookmarks_file=${BASHMARKS_FILE:-~/.bookmarks}

    # Create bookmarks_file if it doesn't exist
    [[ -f $bookmarks_file ]] || touch "$bookmarks_file"
    echo "$bookmarks_file"
}

bookmark (){
  local bookmark_name="$1"
  local bookmarks_file=$(bookmarks_file)

  if [[ -z $bookmark_name ]]; then
    echo 'Invalid name, please provide a name for your bookmark. For example:'
    echo '  bookmark foo'
    return 1
  else
    local bookmark="$(pwd)|$bookmark_name" # Store the bookmark as folder|name

    if grep -q "$bookmark" "$bookmarks_file"; then
      echo "Bookmark already existed"
      return 1
    else
      echo "$bookmark" >> "$bookmarks_file"
      echo "Bookmark '$bookmark_name' saved"
    fi
  fi
} 

# Show a list of the bookmarks
bookmarksshow (){
  awk '{ printf "%-40s %-40s\n",$1,$2}' FS=\| "$bookmarks_file"
}

go(){
  local bookmark_name="$1"

  local bookmark=$( grep "|$bookmark_name$" "$bookmarks_file" )

  if [[ -z $bookmark ]]; then
    echo 'Invalid name, please provide a valid bookmark name. For example:'
    echo '  go foo'
    echo
    echo "To bookmark a folder, go to the folder then do this (naming the bookmark 'foo'):"
    echo '  bookmark foo'
    return 1
  else
    dir=$(eval "echo $(echo "$bookmark" | cut -d\| -f1)")
    cd "$dir" 
  fi
}

_go_complete(){
  # Get a list of bookmark names, then grep for what was entered to narrow the list
  cat "$bookmarks_file" | cut -d\| -f2 | grep "^$2.*"
}

complete -C _go_complete -o default go 
