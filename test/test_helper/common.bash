_common_setup() {
    load "${BATS_TEST_DIRNAME}/test_helper/bats-support/load"
    load "${BATS_TEST_DIRNAME}/test_helper/bats-assert/load"

    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

    export BASHMARKS_FILE="${BATS_TEST_TMPDIR}/bookmarks"

    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/bashmarks.sh"

    export ORIGINAL_DIR="$PWD"
}
