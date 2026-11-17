#!/usr/bin/env bash
# classroom.sh — GitHub Classrooms replacement
# Requires: gh (GitHub CLI), git, jq
#
# Usage: ./classroom.sh <command> <config_file> [options]
#
#   create  <config>          Create one private repo per student from the template
#   report  <config>          Show a report (commits, branches, link) for each student
#   clone   <config> [dir]    Clone all student repos locally  (default: current dir)
#   sync    <config>          Merge template updates into every student repo

set -euo pipefail

# Prevent Git Bash on Windows from converting /repos/... URL paths to filesystem paths
export MSYS_NO_PATHCONV=1

# Global config file path for use in helper functions
CONFIG_FILE=""

# ─── dependency check ────────────────────────────────────────────────────────

check_deps() {
    local missing=0
    for cmd in gh git jq; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "Error: '$cmd' is required but not installed." >&2
            missing=1
        fi
    done
    [[ $missing -eq 0 ]] || exit 1

    if ! gh auth status &>/dev/null; then
        echo "Error: gh CLI is not authenticated. Run 'gh auth login' first." >&2
        exit 1
    fi
}

# ─── config loader ───────────────────────────────────────────────────────────

load_config() {
    local cfg="$1"
    if [[ ! -f "$cfg" ]]; then
        echo "Error: config file '$cfg' not found." >&2
        exit 1
    fi

    # tr -d '\r' strips carriage returns from CRLF line endings (Windows JSON files)
    ORG=$(jq -r '.organization'       "$cfg" | tr -d '\r')
    TEMPLATE_URL=$(jq -r '.template'  "$cfg" | tr -d '\r')
    BRANCH=$(jq -r '.branch'          "$cfg" | tr -d '\r')
    PREFIX=$(jq -r '.homework_prefix' "$cfg" | tr -d '\r')

    # Strip https://github.com/ to get owner/repo format expected by gh
    TEMPLATE_REPO="${TEMPLATE_URL#https://github.com/}"

    # First teacher is the de-facto owner (creates repos)
    OWNER=$(jq -r '.teachers[0]' "$cfg" | tr -d '\r')

    # while-read is used instead of mapfile for bash 3.2 compatibility (macOS default)
    TEACHERS=()
    while IFS= read -r line; do TEACHERS+=("$line"); done \
        < <(jq -r '.teachers[]' "$cfg" | tr -d '\r')

    # Check if it's a team project (projets) or individual assignment (students)
    IS_TEAM_PROJECT=$(jq 'has("projets")' "$cfg")

    if [[ "$IS_TEAM_PROJECT" == "true" ]]; then
        # Load team project structure
        PROJECTS=()
        while IFS= read -r line; do PROJECTS+=("$line"); done \
            < <(jq -r '.projets[].name' "$cfg" | tr -d '\r')

        if [[ "${#PROJECTS[@]}" -eq 0 ]]; then
            echo "Error: no projects found in config." >&2
            exit 1
        fi
    else
        # Load individual student structure
        STUDENTS=()
        while IFS= read -r line; do STUDENTS+=("$line"); done \
            < <(jq -r '.students[]' "$cfg" | tr -d '\r')

        if [[ "${#STUDENTS[@]}" -eq 0 ]]; then
            echo "Error: no students found in config." >&2
            exit 1
        fi
    fi
}

repo_name_for() {
    if [[ "$IS_TEAM_PROJECT" == "true" ]]; then
        echo "${PREFIX}${1}"
    else
        echo "${PREFIX}${1}"
    fi
}

get_project_students() {
    local project_name="$1"
    jq -r ".projets[] | select(.name==\"${project_name}\") | .students[]" "$CONFIG_FILE" | tr -d '\r'
}

# ─── create ──────────────────────────────────────────────────────────────────
# Creates repositories:
# - For individual assignment: one repo per student
# - For team project: one repo per project with multiple students
# In both cases, students get write (read/write) access, teachers get admin.

cmd_create() {
    if [[ "$IS_TEAM_PROJECT" == "true" ]]; then
        cmd_create_team_projects
    else
        cmd_create_individual
    fi
}

cmd_create_individual() {
    echo "=== Creating student repositories ==="
    echo "    Org       : $ORG"
    echo "    Template  : $TEMPLATE_REPO  (branch: $BRANCH)"
    echo "    Owner     : $OWNER"
    echo ""

    for STUDENT in "${STUDENTS[@]}"; do
        REPO=$(repo_name_for "$STUDENT")
        FULL_REPO="${ORG}/${REPO}"
        URL="https://github.com/${FULL_REPO}"

        echo "→ $FULL_REPO"

        # Create from template only if it doesn't already exist
        if gh repo view "$FULL_REPO" &>/dev/null; then
            echo "  [skip] Repository already exists → $URL"
        else
            gh repo create "$FULL_REPO" \
                --template "$TEMPLATE_REPO" \
                --private \
                --clone=false
            echo "  [ok]   Created from template"
        fi

        # Grant student write (push) access — not admin
        gh api --method PUT "/repos/${FULL_REPO}/collaborators/${STUDENT}" \
            -f permission=push > /dev/null
        echo "  [ok]   ${STUDENT} → push"

        # Grant every teacher admin access
        for TEACHER in "${TEACHERS[@]}"; do
            gh api --method PUT "/repos/${FULL_REPO}/collaborators/${TEACHER}" \
                -f permission=admin > /dev/null
            echo "  [ok]   ${TEACHER} → admin"
        done

        echo "  URL: $URL"
        echo ""
    done

    echo "=== Done ==="
}

cmd_create_team_projects() {
    echo "=== Creating team project repositories ==="
    echo "    Org       : $ORG"
    echo "    Template  : $TEMPLATE_REPO  (branch: $BRANCH)"
    echo "    Owner     : $OWNER"
    echo ""

    for PROJECT_NAME in "${PROJECTS[@]}"; do
        REPO=$(repo_name_for "$PROJECT_NAME")
        FULL_REPO="${ORG}/${REPO}"
        URL="https://github.com/${FULL_REPO}"

        echo "→ $FULL_REPO"

        # Create from template only if it doesn't already exist
        if gh repo view "$FULL_REPO" &>/dev/null; then
            echo "  [skip] Repository already exists → $URL"
        else
            gh repo create "$FULL_REPO" \
                --template "$TEMPLATE_REPO" \
                --private \
                --clone=false
            echo "  [ok]   Created from template"
        fi

        # Grant each team member write (push) access
        while IFS= read -r STUDENT; do
            if [[ -n "$STUDENT" ]]; then
                gh api --method PUT "/repos/${FULL_REPO}/collaborators/${STUDENT}" \
                    -f permission=push > /dev/null
                echo "  [ok]   ${STUDENT} → push"
            fi
        done < <(get_project_students "$PROJECT_NAME")

        # Grant every teacher admin access
        for TEACHER in "${TEACHERS[@]}"; do
            gh api --method PUT "/repos/${FULL_REPO}/collaborators/${TEACHER}" \
                -f permission=admin > /dev/null
            echo "  [ok]   ${TEACHER} → admin"
        done

        echo "  URL: $URL"
        echo ""
    done

    echo "=== Done ==="
}

# ─── report ──────────────────────────────────────────────────────────────────
# Displays a table with commit count, branches, and repo URL.
# Note: commit count is capped at 100 per GitHub API page.

cmd_report() {
    if [[ "$IS_TEAM_PROJECT" == "true" ]]; then
        cmd_report_team_projects
    else
        cmd_report_individual
    fi
}

cmd_report_individual() {
    echo "=== Student Repository Report ==="
    echo "    Org    : $ORG"
    echo "    Prefix : $PREFIX"
    echo ""
    printf "%-40s %8s  %-35s  %s\n" "Repository" "Commits" "Branches" "URL"
    printf "%-40s %8s  %-35s  %s\n" "─────────────────────────────────────────" "───────" "───────────────────────────────────" "───────────────────────────────────"

    for STUDENT in "${STUDENTS[@]}"; do
        REPO=$(repo_name_for "$STUDENT")
        FULL_REPO="${ORG}/${REPO}"
        URL="https://github.com/${FULL_REPO}"

        # Commit count authored by this student (max 100 per page)
        COMMIT_COUNT=$(gh api \
            "/repos/${FULL_REPO}/commits?author=${STUDENT}&per_page=100" \
            --jq 'length' 2>/dev/null || echo "?")

        # Branch names joined with ", "
        BRANCHES=$(gh api \
            "/repos/${FULL_REPO}/branches?per_page=100" \
            --jq '[.[].name] | join(", ")' 2>/dev/null || echo "N/A")

        printf "%-40s %8s  %-35s  %s\n" \
            "$REPO" "$COMMIT_COUNT" "${BRANCHES:0:35}" "$URL"
    done

    echo ""
}

cmd_report_team_projects() {
    echo "=== Team Project Repository Report ==="
    echo "    Org    : $ORG"
    echo "    Prefix : $PREFIX"
    echo ""
    printf "%-40s %8s  %-35s  %s\n" "Repository" "Commits" "Branches" "URL"
    printf "%-40s %8s  %-35s  %s\n" "─────────────────────────────────────────" "───────" "───────────────────────────────────" "───────────────────────────────────"

    for PROJECT_NAME in "${PROJECTS[@]}"; do
        REPO=$(repo_name_for "$PROJECT_NAME")
        FULL_REPO="${ORG}/${REPO}"
        URL="https://github.com/${FULL_REPO}"

        # Total commit count in repo
        COMMIT_COUNT=$(gh api \
            "/repos/${FULL_REPO}/commits?per_page=100" \
            --jq 'length' 2>/dev/null || echo "?")

        # Branch names joined with ", "
        BRANCHES=$(gh api \
            "/repos/${FULL_REPO}/branches?per_page=100" \
            --jq '[.[].name] | join(", ")' 2>/dev/null || echo "N/A")

        printf "%-40s %8s  %-35s  %s\n" \
            "$REPO" "$COMMIT_COUNT" "${BRANCHES:0:35}" "$URL"
    done

    echo ""
}

# ─── clone ───────────────────────────────────────────────────────────────────
# Clones each repo into CLONE_DIR (default: current directory).
# If the directory already exists, does a fast-forward pull instead.

cmd_clone() {
    if [[ "$IS_TEAM_PROJECT" == "true" ]]; then
        cmd_clone_team_projects
    else
        cmd_clone_individual
    fi
}

cmd_clone_individual() {
    local TARGET_DIR="$CLONE_DIR"
    echo "=== Cloning student repositories → '${TARGET_DIR}' ==="
    mkdir -p "$TARGET_DIR"

    for STUDENT in "${STUDENTS[@]}"; do
        REPO=$(repo_name_for "$STUDENT")
        FULL_REPO="${ORG}/${REPO}"
        DEST="${TARGET_DIR}/${REPO}"

        echo ""
        echo "→ $REPO"

        if [[ -d "${DEST}/.git" ]]; then
            echo "  [exists] Pulling latest changes..."
            git -C "$DEST" pull --ff-only
        else
            gh repo clone "$FULL_REPO" "$DEST"
            echo "  [ok] Cloned → $DEST"
        fi
    done

    echo ""
    echo "=== Done ==="
}

cmd_clone_team_projects() {
    local TARGET_DIR="$CLONE_DIR"
    echo "=== Cloning team project repositories → '${TARGET_DIR}' ==="
    mkdir -p "$TARGET_DIR"

    for PROJECT_NAME in "${PROJECTS[@]}"; do
        REPO=$(repo_name_for "$PROJECT_NAME")
        FULL_REPO="${ORG}/${REPO}"
        DEST="${TARGET_DIR}/${REPO}"

        echo ""
        echo "→ $REPO"

        if [[ -d "${DEST}/.git" ]]; then
            echo "  [exists] Pulling latest changes..."
            git -C "$DEST" pull --ff-only
        else
            gh repo clone "$FULL_REPO" "$DEST"
            echo "  [ok] Cloned → $DEST"
        fi
    done

    echo ""
    echo "=== Done ==="
}

# ─── sync ────────────────────────────────────────────────────────────────────
# Merges new commits from the template into each repo.
# Since repos are created from a template (not a fork), upstream must be
# added manually. Uses a temporary directory — no permanent local clone needed.
# Student's work is preserved; merge conflicts require manual resolution.

cmd_sync() {
    if [[ "$IS_TEAM_PROJECT" == "true" ]]; then
        cmd_sync_team_projects
    else
        cmd_sync_individual
    fi
}

cmd_sync_individual() {
    echo "=== Syncing student repos from template ==="
    echo "    Template : $TEMPLATE_URL  (branch: $BRANCH)"
    echo ""

    local WORK_DIR
    WORK_DIR=$(mktemp -d)
    trap 'rm -rf "$WORK_DIR"' EXIT

    for STUDENT in "${STUDENTS[@]}"; do
        REPO=$(repo_name_for "$STUDENT")
        FULL_REPO="${ORG}/${REPO}"
        LOCAL="${WORK_DIR}/${REPO}"

        echo "→ $FULL_REPO"

        gh repo clone "$FULL_REPO" "$LOCAL" -- --quiet
        pushd "$LOCAL" > /dev/null

        git remote add upstream "$TEMPLATE_URL"
        git fetch upstream "$BRANCH" --quiet

        if git merge "upstream/${BRANCH}" \
                --no-edit \
                -m "chore: sync updates from template ${TEMPLATE_REPO}@${BRANCH}"; then
            git push origin "HEAD:${BRANCH}"
            echo "  [ok] Synced and pushed"
        else
            echo "  [!]  Merge conflict in ${REPO} — aborting merge." >&2
            echo "       Manual resolution required. Clone the repo and merge manually:" >&2
            echo "         gh repo clone ${FULL_REPO} && cd ${REPO}" >&2
            echo "         git remote add upstream ${TEMPLATE_URL}" >&2
            echo "         git fetch upstream && git merge upstream/${BRANCH}" >&2
            git merge --abort 2>/dev/null || true
        fi

        popd > /dev/null
    done

    echo ""
    echo "=== Done ==="
}

cmd_sync_team_projects() {
    echo "=== Syncing team project repos from template ==="
    echo "    Template : $TEMPLATE_URL  (branch: $BRANCH)"
    echo ""

    local WORK_DIR
    WORK_DIR=$(mktemp -d)
    trap 'rm -rf "$WORK_DIR"' EXIT

    for PROJECT_NAME in "${PROJECTS[@]}"; do
        REPO=$(repo_name_for "$PROJECT_NAME")
        FULL_REPO="${ORG}/${REPO}"
        LOCAL="${WORK_DIR}/${REPO}"

        echo "→ $FULL_REPO"

        gh repo clone "$FULL_REPO" "$LOCAL" -- --quiet
        pushd "$LOCAL" > /dev/null

        git remote add upstream "$TEMPLATE_URL"
        git fetch upstream "$BRANCH" --quiet

        if git merge "upstream/${BRANCH}" \
                --no-edit \
                -m "chore: sync updates from template ${TEMPLATE_REPO}@${BRANCH}"; then
            git push origin "HEAD:${BRANCH}"
            echo "  [ok] Synced and pushed"
        else
            echo "  [!]  Merge conflict in ${REPO} — aborting merge." >&2
            echo "       Manual resolution required. Clone the repo and merge manually:" >&2
            echo "         gh repo clone ${FULL_REPO} && cd ${REPO}" >&2
            echo "         git remote add upstream ${TEMPLATE_URL}" >&2
            echo "         git fetch upstream && git merge upstream/${BRANCH}" >&2
            git merge --abort 2>/dev/null || true
        fi

        popd > /dev/null
    done

    echo ""
    echo "=== Done ==="
}

# ─── help ────────────────────────────────────────────────────────────────────

cmd_help() {
    cat <<'EOF'
Usage: ./classroom.sh <command> <config_file> [options]

Commands:
  create  <config>          Create one private repo per student from the template.
                            Students get write (push) access; teachers get admin.

  report  <config>          Print a table showing commit count, branches, and URL
                            for every student repo.

  clone   <config> [dir]    Clone all student repos locally.
                            If a repo is already cloned, pulls the latest instead.
                            Default directory: current working directory.

  sync    <config>          Merge new commits from the template into every student
                            repo. Does not overwrite student work; reports conflicts.

Examples:
  ./classroom.sh create config_417.json
  ./classroom.sh report config_417.json
  ./classroom.sh clone  config_417.json ./clones
  ./classroom.sh sync   config_417.json

Prerequisites:
  - gh   (GitHub CLI)  — https://cli.github.com
  - git
  - jq                 — https://stedolan.github.io/jq
  - gh auth login      (must be authenticated before running any command)
EOF
}

# ─── entry point ─────────────────────────────────────────────────────────────

COMMAND="${1:-help}"
CONFIG_FILE="${2:-}"
CLONE_DIR="${3:-.}"     # Optional 3rd arg used by 'clone' command

check_deps

if [[ "$COMMAND" != "help" ]]; then
    if [[ -z "$CONFIG_FILE" ]]; then
        echo "Error: a config file is required." >&2
        echo ""
        cmd_help
        exit 1
    fi
    load_config "$CONFIG_FILE"
fi

case "$COMMAND" in
    create) cmd_create ;;
    report) cmd_report ;;
    clone)  cmd_clone  ;;
    sync)   cmd_sync   ;;
    help)   cmd_help   ;;
    *)
        echo "Error: unknown command '$COMMAND'." >&2
        echo ""
        cmd_help
        exit 1
        ;;
esac
