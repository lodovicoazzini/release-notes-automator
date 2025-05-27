#!/bin/bash
set -e

REPO="${1:-$GITHUB_REPOSITORY}"
LABEL_CONFIG_JSON=$2
MILESTONE_VERSION=$3

if [ -z "$MILESTONE_VERSION" ]; then
  MILESTONE_VERSION="${GITHUB_REF#refs/tags/}"
fi

if [ -z "$LABEL_CONFIG_JSON" ]; then
  echo "❌ ERROR: Label configuration JSON is missing."
  exit 1
fi

echo "🔗 Issues will be fetched from: $REPO"
echo "🏷 Milestone version: $MILESTONE_VERSION"
echo "⚙ Label configuration: $LABEL_CONFIG_JSON"

# -------------------------
# Authenticate explicitly for Repo B (Issues Repository)
# -------------------------
if [ -n "$ISSUES_REPOSITORY_TOKEN" ]; then
  # Backup GH_TOKEN temporarily
  ORIGINAL_GH_TOKEN="$GH_TOKEN"
  unset GH_TOKEN
  echo "$ISSUES_REPOSITORY_TOKEN" | gh auth login --with-token
else
  echo "❌ ERROR: ISSUES_REPOSITORY_TOKEN not provided."
  exit 1
fi

# -------------------------
# Check milestone exists in Issues Repository
# -------------------------
echo "🔍 Validating milestone exists in $REPO..."

# Fetch API response
MILESTONES_RESPONSE=$(gh api -H "Accept: application/vnd.github.v3+json" "/repos/$REPO/milestones" 2>&1)

# Check if it's valid JSON
if ! echo "$MILESTONES_RESPONSE" | jq empty >/dev/null 2>&1; then
  echo "❌ ERROR: GitHub API did not return valid JSON. Here's what was received:"
  echo "$MILESTONES_RESPONSE"
  exit 1
fi

# Try to extract the milestone
MILESTONE_EXISTS=$(echo "$MILESTONES_RESPONSE" | jq -r --arg version "$MILESTONE_VERSION" '.[] | select(.title == $version) | .number')

if [ -z "$MILESTONE_EXISTS" ]; then
  echo "❌ ERROR: Milestone '$MILESTONE_VERSION' does not exist in $REPO."
  exit 1
fi

# -------------------------
# Determine if LABEL_CONFIG_JSON is a file or raw JSON
# -------------------------
if [ -f "$LABEL_CONFIG_JSON" ]; then
  echo "📄 Detected label config as file: $LABEL_CONFIG_JSON"
  LABEL_JSON_CONTENT=$(cat "$LABEL_CONFIG_JSON")
else
  echo "🧾 Detected label config as raw JSON string"
  LABEL_JSON_CONTENT="$LABEL_CONFIG_JSON"
fi

# -------------------------
# Validate LABEL_CONFIG_JSON is valid JSON
# -------------------------
echo "🔍 Validating label config JSON..."
if ! echo "$LABEL_JSON_CONTENT" | jq empty >/dev/null 2>&1; then
  echo "❌ ERROR: Invalid label configuration JSON. Here's what was received:"
  echo "$LABEL_JSON_CONTENT"
  exit 1
fi

# -------------------------
# Generate changelog
# -------------------------
CHANGELOG_FILE="changelog.md"
echo "## Release Notes for $MILESTONE_VERSION" > "$CHANGELOG_FILE"
echo "" >> "$CHANGELOG_FILE"

LABEL_COUNT=$(echo "$LABEL_JSON_CONTENT" | jq '. | length')

for i in $(seq 0 $(($LABEL_COUNT - 1))); do
  echo "🔍 Processing label index $i..."  ### DEBUG

  LABEL_NAME=$(echo "$LABEL_JSON_CONTENT" | jq -r ".[$i].label")
  TEMPLATE=$(echo "$LABEL_JSON_CONTENT" | jq -r ".[$i].template")
  SECTION_TITLE=$(echo "$LABEL_JSON_CONTENT" | jq -r ".[$i].section_title")

  echo "📌 Section: $SECTION_TITLE (label: $LABEL_NAME)"  ### DEBUG

  echo "### $SECTION_TITLE" >> "$CHANGELOG_FILE"
  echo "" >> "$CHANGELOG_FILE"

  ISSUES=$(gh issue list --repo "$REPO" --milestone "$MILESTONE_VERSION" --state closed --label "$LABEL_NAME" --json number,title --jq '.[]')

  if [ -z "$ISSUES" ]; then
    echo "_No issues found for label '$LABEL_NAME'_" >> "$CHANGELOG_FILE"
  else
    echo "$ISSUES" | jq -c '.' | while read -r issue; do
      NUMBER=$(echo "$issue" | jq '.number')
      TITLE=$(echo "$issue" | jq -r '.title')
      ENTRY=$(echo "$TEMPLATE" | sed "s/\$NUMBER/$NUMBER/g" | sed "s/\$TITLE/$TITLE/g")
      echo "$ENTRY" >> "$CHANGELOG_FILE"
    done
  fi

  echo "" >> "$CHANGELOG_FILE"
done

echo "✅ Changelog generated:"
cat "$CHANGELOG_FILE"

# -------------------------
# IMPORTANT: Reset authentication to use GH_TOKEN for Repo A
# -------------------------
gh auth logout --hostname github.com

# -------------------------
# Restore GH_TOKEN for Repo A (Release operations)
# -------------------------
export GH_TOKEN="$ORIGINAL_GH_TOKEN"

# Now gh will use GH_TOKEN automatically for all further calls
# No login needed, just execute the release edit
gh release edit "$MILESTONE_VERSION" --repo "$GITHUB_REPOSITORY" --notes-file "$CHANGELOG_FILE"
