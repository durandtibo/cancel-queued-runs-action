#!/usr/bin/env bats
#
# action.yaml, README.md and scripts/cancel.sh must describe the same inputs and
# outputs. Nothing else checks it: a renamed input, a changed default or an
# output that is documented but not exposed would pass every other test.
#
# The files are parsed with awk (no YAML library is needed). The helpers take
# the files from ACTION_FILE and README_FILE so that they can be tested on
# modified copies.

setup() {
  ACTION_FILE="$BATS_TEST_DIRNAME/../action.yaml"
  README_FILE="$BATS_TEST_DIRNAME/../README.md"
  SCRIPT_FILE="$BATS_TEST_DIRNAME/../scripts/cancel.sh"
  MOCK_DIR="$BATS_TEST_DIRNAME/mocks"
}

teardown() {
  rm -rf "$MOCK_DIR"
}

# --------------------------------------------------------
# Helpers
# --------------------------------------------------------

# The names of the inputs of action.yaml, one per line
action_inputs() {
  awk '/^inputs:/ {f=1; next} /^[a-z]+:/ {f=0} f && /^  [a-z-]+:$/ {gsub(/[: ]/, ""); print}' "$ACTION_FILE"
}

# The names of the outputs of action.yaml, one per line
action_outputs() {
  awk '/^outputs:/ {f=1; next} /^[a-z]+:/ {f=0} f && /^  [a-z-]+:$/ {gsub(/[: ]/, ""); print}' "$ACTION_FILE"
}

# The default of an input of action.yaml, without quotes ("" gives an empty string)
# Args: $1 - input name
action_default() {
  awk -v name="$1" '
    /^inputs:/ {f=1; next}
    /^[a-z]+:/ {f=0}
    f && /^  [a-z-]+:$/ {gsub(/[: ]/, ""); cur=$0; next}
    f && cur == name && /^    default:/ {sub(/^    default: */, ""); print; exit}
  ' "$ACTION_FILE" | sed -E 's/^"(.*)"$/\1/'
}

# The description of an input or an output of action.yaml, on one line, without quotes
# Args: $1 - section ("inputs" or "outputs"), $2 - name
action_description() {
  awk -v section="$1" -v name="$2" '
    $0 ~ "^" section ":" {f=1; next}
    /^[a-z]+:/ {f=0}
    f && /^  [a-z-]+:$/ {gsub(/[: ]/, ""); cur=$0; d=0; next}
    f && cur == name && /^    description:/ {
      sub(/^    description: */, "")
      if ($0 == ">") {d=1; next}
      print; exit
    }
    f && cur == name && d && /^      / {sub(/^ +/, ""); text = text (text == "" ? "" : " ") $0; next}
    f && cur == name && d && !/^      / {print text; exit}
  ' "$ACTION_FILE" | sed -E "s/^\"(.*)\"\$/\1/; s/^'(.*)'\$/\1/"
}

# The description documented in the README for an input or an output
# Args: $1 - section title, $2 - name
readme_description() {
  readme_rows "$1" | awk -F'|' -v name="$2" -v last="$([ "$1" = Inputs ] && echo 4 || echo 3)" '
    {n = $2; gsub(/[ `]/, "", n)}
    n == name {d = $last; sub(/^ +/, "", d); sub(/ +$/, "", d); print d; exit}
  '
}

# The rows of the table of a section of the README ("Inputs" or "Outputs")
# Args: $1 - section title (last word of the "## " heading)
readme_rows() {
  awk -v title="$1" '
    /^## / {f = ($NF == title); next}
    f && /^\| `/ {print}
  ' "$README_FILE"
}

# The names documented in the README, one per line
# Args: $1 - section title
readme_names() {
  readme_rows "$1" | awk -F'|' '{gsub(/[ `]/, "", $2); print $2}'
}

# The default documented in the README for an input, without quotes
# Args: $1 - input name
readme_default() {
  readme_rows Inputs | awk -F'|' -v name="$1" '
    {n = $2; gsub(/[ `]/, "", n)}
    n == name {print $3; exit}
  ' | sed -E 's/^ *`([^`]*)`.*/\1/; s/^"(.*)"$/\1/'
}

# The names present in the first list and not in the second one
# Args: $1, $2 - lists of names, one per line
only_in_first() {
  comm -23 <(echo "$1" | sort) <(echo "$2" | sort)
}

# --------------------------------------------------------
# Inputs
# --------------------------------------------------------

@test "sync: action.yaml has inputs" {
  [ "$(action_inputs | wc -l | tr -d ' ')" -ge 9 ]
}

@test "sync: every input of action.yaml is documented in the README" {
  missing=$(only_in_first "$(action_inputs)" "$(readme_names Inputs)")

  [ -z "$missing" ] || { echo "not in the README: $missing"; false; }
}

@test "sync: every input of the README exists in action.yaml" {
  stale=$(only_in_first "$(readme_names Inputs)" "$(action_inputs)")

  [ -z "$stale" ] || { echo "not in action.yaml: $stale"; false; }
}

@test "sync: the default of every input is the same in action.yaml and in the README" {
  for name in $(action_inputs); do
    [ "$(action_default "$name")" = "$(readme_default "$name")" ] ||
      { echo "default of $name: action.yaml='$(action_default "$name")' README='$(readme_default "$name")'"; false; }
  done
}

@test "sync: every input of action.yaml has a default" {
  for name in $(action_inputs); do
    awk -v name="$name" '
      /^inputs:/ {f=1; next}
      /^[a-z]+:/ {f=0}
      f && /^  [a-z-]+:$/ {gsub(/[: ]/, ""); cur=$0; next}
      f && cur == name && /^    default:/ {found=1}
      END {exit !found}
    ' "$ACTION_FILE" || { echo "no default for $name"; false; }
  done
}

@test "sync: the description of every input is the same in action.yaml and in the README" {
  for name in $(action_inputs); do
    [ "$(action_description inputs "$name")" = "$(readme_description Inputs "$name")" ] ||
      { echo "description of $name: action.yaml='$(action_description inputs "$name")' README='$(readme_description Inputs "$name")'"; false; }
  done
}

@test "sync: the description of every output is the same in action.yaml and in the README" {
  for name in $(action_outputs); do
    [ "$(action_description outputs "$name")" = "$(readme_description Outputs "$name")" ] ||
      { echo "description of $name: action.yaml='$(action_description outputs "$name")' README='$(readme_description Outputs "$name")'"; false; }
  done
}

@test "sync: every input of action.yaml has a description" {
  for name in $(action_inputs); do
    awk -v name="$name" '
      /^inputs:/ {f=1; next}
      /^[a-z]+:/ {f=0}
      f && /^  [a-z-]+:$/ {gsub(/[: ]/, ""); cur=$0; next}
      f && cur == name && /^    description:/ {found=1}
      END {exit !found}
    ' "$ACTION_FILE" || { echo "no description for $name"; false; }
  done
}

# --------------------------------------------------------
# Outputs
# --------------------------------------------------------

@test "sync: every output of action.yaml is documented in the README" {
  missing=$(only_in_first "$(action_outputs)" "$(readme_names Outputs)")

  [ -z "$missing" ] || { echo "not in the README: $missing"; false; }
}

@test "sync: every output of the README exists in action.yaml" {
  stale=$(only_in_first "$(readme_names Outputs)" "$(action_outputs)")

  [ -z "$stale" ] || { echo "not in action.yaml: $stale"; false; }
}

@test "sync: every output of action.yaml exposes the output of the same name of the cancel step" {
  for name in $(action_outputs); do
    grep -qF "value: \${{ steps.cancel.outputs.$name }}" "$ACTION_FILE" ||
      { echo "output $name does not expose steps.cancel.outputs.$name"; false; }
  done
}

@test "sync: every output of action.yaml is written by the script" {
  for name in $(action_outputs); do
    awk '/^write_outputs\(\)/ {f=1} f {print} f && /^}/ {exit}' "$SCRIPT_FILE" | grep -q "$name=" ||
      { echo "the script does not write $name"; false; }
  done
}

@test "sync: every output written by the script is exposed by action.yaml" {
  # only write_outputs writes the outputs
  in_function=$(awk '/^write_outputs\(\)/ {f=1} f {print} f && /^}/ {exit}' "$SCRIPT_FILE" | sed 's/\\n/ /g' | grep -oE '[a-z-]+-(count|ids)=' | sed -E 's/=$//')
  [ -n "$in_function" ]

  missing=$(only_in_first "$in_function" "$(action_outputs)")

  [ -z "$missing" ] || { echo "not exposed by action.yaml: $missing"; false; }
}

@test "sync: every output of the script is listed in the header of the script" {
  for name in $(action_outputs); do
    awk '/^set -euo/ {exit} {print}' "$SCRIPT_FILE" | grep -q "$name" ||
      { echo "$name is not mentioned in the header of the script"; false; }
  done
}

# --------------------------------------------------------
# Passing the inputs to the script
# --------------------------------------------------------

@test "sync: every input is passed to the script through env" {
  for name in $(action_inputs); do
    [ "$(grep -cF "\${{ inputs.$name }}" "$ACTION_FILE")" -eq 1 ] ||
      { echo "input $name must be used exactly once"; false; }
    grep -E "^        [A-Z_]+: \\$\{\{ inputs\\.$name \}\}$" "$ACTION_FILE" > /dev/null ||
      { echo "input $name is not passed in the env: block"; false; }
  done
}

@test "sync: every environment variable passed by action.yaml is documented in the header of the script" {
  vars=$(grep -E '^        [A-Z_]+: \$\{\{ inputs\.' "$ACTION_FILE" | sed -E 's/^ +([A-Z_]+):.*/\1/')
  [ -n "$vars" ]

  for var in $vars; do
    awk '/^set -euo/ {exit} {print}' "$SCRIPT_FILE" | grep -qE "^#   $var( |,)" ||
      { echo "$var is not documented in the header of the script"; false; }
  done
}

@test "sync: no input is interpolated in a run: line" {
  [ "$(grep -E '^\s*run:' "$ACTION_FILE" | grep -c 'inputs\.' || true)" -eq 0 ]
}

@test "sync: every run: step of action.yaml sets shell: bash" {
  runs=$(grep -cE '^\s*run:' "$ACTION_FILE")
  shells=$(grep -cE '^\s*shell: bash$' "$ACTION_FILE")

  [ "$runs" -ge 1 ]
  [ "$runs" -eq "$shells" ]
}

# --------------------------------------------------------
# The helpers detect a drift (tests of the checks themselves)
# --------------------------------------------------------

# Copies action.yaml and README.md to the mock directory and uses the copies
use_copies() {
  mkdir -p "$MOCK_DIR"
  cp "$ACTION_FILE" "$MOCK_DIR/action.yaml"
  cp "$README_FILE" "$MOCK_DIR/README.md"
  ACTION_FILE="$MOCK_DIR/action.yaml"
  README_FILE="$MOCK_DIR/README.md"
}

@test "sync helpers: an input removed from the README is reported" {
  use_copies
  grep -v '^| `branch`' "$README_FILE" > "$README_FILE.new" && mv "$README_FILE.new" "$README_FILE"

  [ "$(only_in_first "$(action_inputs)" "$(readme_names Inputs)")" = "branch" ]
}

@test "sync helpers: an input renamed in action.yaml is reported on both sides" {
  use_copies
  sed -i.bak 's/^  dry-run:$/  dryrun:/' "$ACTION_FILE"

  [ "$(only_in_first "$(action_inputs)" "$(readme_names Inputs)")" = "dryrun" ]
  [ "$(only_in_first "$(readme_names Inputs)" "$(action_inputs)")" = "dry-run" ]
}

@test "sync helpers: a changed default is reported" {
  use_copies
  sed -i.bak 's/^    default: "24"$/    default: "48"/' "$ACTION_FILE"

  [ "$(action_default max-age-hours)" = "48" ]
  [ "$(readme_default max-age-hours)" = "24" ]
}

@test "sync helpers: the default of an empty string input is read as empty on both sides" {
  [ -z "$(action_default workflow)" ]
  [ "$(readme_default workflow)" = '' ] || [ "$(readme_default workflow)" = '""' ]
  [ "$(action_default workflow)" = "$(readme_default workflow)" ]
}

@test "sync helpers: an output removed from the README is reported" {
  use_copies
  grep -v '^| `cancelled-run-ids`' "$README_FILE" > "$README_FILE.new" && mv "$README_FILE.new" "$README_FILE"

  [ "$(only_in_first "$(action_outputs)" "$(readme_names Outputs)")" = "cancelled-run-ids" ]
}

@test "sync helpers: a changed description is reported" {
  use_copies
  sed -i.bak 's/Target repository, owner\/name/Another repository/' "$ACTION_FILE"

  [ "$(action_description inputs repo)" = "Another repository" ]
  [ "$(readme_description Inputs repo)" = "Target repository, owner/name" ]
}

@test "sync helpers: a folded description is read on one line" {
  [[ "$(action_description inputs max-age-hours)" == "Runs older than this many hours"*"so a re-run restarts it" ]] || false
}
