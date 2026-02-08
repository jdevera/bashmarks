setup() {
    load 'test_helper/common'
    _common_setup
}

teardown() {
    cd "$ORIGINAL_DIR" || return
}

# -------------------------------------------------------------------
# Core bookmark/cdd functionality
# -------------------------------------------------------------------

@test "bookmark saves an entry to the file" {
    cd /tmp
    run bookmark tmpmark
    assert_success
    assert_output "Bookmark 'tmpmark' saved"
    run cat "$BASHMARKS_FILE"
    assert_output "/tmp|tmpmark"
}

@test "bookmark with no name fails with usage message" {
    run bookmark
    assert_failure
    assert_output --partial "Invalid name, please provide a name"
}

@test "bookmark rejects duplicate names" {
    echo "/tmp|dupmark" >>"$BASHMARKS_FILE"
    cd /var
    run bookmark dupmark
    assert_failure
    assert_output --partial "already exists"
}

@test "cdd navigates to a bookmarked directory" {
    local resolved_tmp
    resolved_tmp=$(cd /tmp && pwd -P)
    echo "/tmp|navmark" >>"$BASHMARKS_FILE"
    cdd navmark
    assert_equal "$(pwd -P)" "$resolved_tmp"
}

@test "cdd with unknown name fails with error message" {
    run cdd nosuchmark
    assert_failure
    assert_output --partial "Invalid name, please provide a valid bookmark name"
}

@test "cdd ? lists all bookmarks" {
    echo "/tmp|alpha" >>"$BASHMARKS_FILE"
    echo "/var|beta" >>"$BASHMARKS_FILE"
    run cdd '?'
    assert_success
    assert_output --partial "alpha"
    assert_output --partial "beta"
}

@test "cdd --check reports OK for a valid file" {
    echo "/tmp|good" >>"$BASHMARKS_FILE"
    run cdd --check
    assert_success
    assert_output --partial "Bookmarks OK"
}

@test "cdd --check reports errors for malformed lines" {
    echo "nopipe" >>"$BASHMARKS_FILE"
    run cdd --check
    assert_failure
    assert_output --partial "Invalid format"
}

# -------------------------------------------------------------------
# Include functionality
# -------------------------------------------------------------------

@test "cdd ? shows bookmarks from main and included files" {
    local inc_file="${BATS_TEST_TMPDIR}/extra_bookmarks"
    echo "/var|inc_mark" >"$inc_file"
    echo "#include ${inc_file}" >>"$BASHMARKS_FILE"
    echo "/tmp|main_mark" >>"$BASHMARKS_FILE"
    run cdd '?'
    assert_success
    assert_output --partial "main_mark"
    assert_output --partial "inc_mark"
}

@test "cdd navigates to a bookmark from an included file" {
    local resolved_tmp
    resolved_tmp=$(cd /tmp && pwd -P)
    local inc_file="${BATS_TEST_TMPDIR}/extra_bookmarks"
    echo "/tmp|inc_nav" >"$inc_file"
    echo "#include ${inc_file}" >>"$BASHMARKS_FILE"
    cdd inc_nav
    assert_equal "$(pwd -P)" "$resolved_tmp"
}

@test "bookmark rejects duplicates that exist in an included file" {
    local inc_file="${BATS_TEST_TMPDIR}/extra_bookmarks"
    echo "/tmp|shared_name" >"$inc_file"
    echo "#include ${inc_file}" >>"$BASHMARKS_FILE"
    cd /var
    run bookmark shared_name
    assert_failure
    assert_output --partial "already exists"
}

@test "cdd --check warns about missing included files" {
    echo "#include /no/such/file.txt" >>"$BASHMARKS_FILE"
    run cdd --check
    assert_success
    assert_output --partial "Warning: included file not found"
}

@test "cdd --check detects duplicates across files" {
    local inc_file="${BATS_TEST_TMPDIR}/extra_bookmarks"
    echo "/var|dup_across" >"$inc_file"
    echo "#include ${inc_file}" >>"$BASHMARKS_FILE"
    echo "/tmp|dup_across" >>"$BASHMARKS_FILE"
    run cdd --check
    assert_failure
    assert_output --partial "Duplicate bookmark name 'dup_across'"
}

@test "tab completion includes names from all files" {
    local inc_file="${BATS_TEST_TMPDIR}/extra_bookmarks"
    echo "/var|comp_inc" >"$inc_file"
    echo "#include ${inc_file}" >>"$BASHMARKS_FILE"
    echo "/tmp|comp_main" >>"$BASHMARKS_FILE"
    run __complete_bashmarks "" "comp_"
    assert_success
    assert_output --partial "comp_inc"
    assert_output --partial "comp_main"
}

@test "self-include is silently skipped" {
    echo "#include ${BASHMARKS_FILE}" >>"$BASHMARKS_FILE"
    echo "/tmp|self_test" >>"$BASHMARKS_FILE"
    run cdd '?'
    assert_success
    # The bookmark should appear exactly once (no infinite loop or duplication)
    local count
    count=$(echo "$output" | grep -c "self_test")
    assert_equal "$count" "1"
}

@test "comments and blank lines are ignored" {
    cat >"$BASHMARKS_FILE" <<'EOF'
# This is a comment
/tmp|real_mark

# Another comment
EOF
    run cdd '?'
    assert_success
    assert_output --partial "real_mark"
    refute_output --partial "# This is a comment"
    refute_output --partial "# Another comment"
}

@test "missing included files are silently skipped during normal operations" {
    echo "#include /does/not/exist.txt" >>"$BASHMARKS_FILE"
    echo "/tmp|still_works" >>"$BASHMARKS_FILE"
    run cdd '?'
    assert_success
    assert_output --partial "still_works"
    refute_output --partial "not found"
    refute_output --partial "error"
}
