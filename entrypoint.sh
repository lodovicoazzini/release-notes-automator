#!/bin/bash
set -e

REPO="${1:-$GITHUB_REPOSITORY}"
LABEL_CONFIG_JSON=$2
MILESTONE_VERSION=$3

if [ -z "$MILESTONE_VERSION" ]; then
  MILESTONE_VERSION="${GITHUB_REF#refs/tags/}"
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
MILESTONE_EXISTS=$(gh api -H "Accept: application/vnd.github.v3+json" "/repos/$REPO/milestones" | jq -r ".[] | select(.title==\"$MILESTONE_VERSION\") | .number")
if [ -z "$MILESTONE_EXISTS" ]; then
  echo "❌ ERROR: Milestone '$MILESTONE_VERSION' does not exist in $REPO."
  exit 1
fi

# -------------------------
# Generate changelog
# -------------------------
CHANGELOG_FILE="changelog.md"
echo "## Release Notes for $MILESTONE_VERSION" > "$CHANGELOG_FILE"
echo "" >> "$CHANGELOG_FILE"

LABEL_COUNT=$(echo "$LABEL_CONFIG_JSON" | jq '. | length')

for i in $(seq 0 $(($LABEL_COUNT - 1))); do
  LABEL_NAME=$(echo "$LABEL_CONFIG_JSON" | jq -r ".[$i].label")
  TEMPLATE=$(echo "$LABEL_CONFIG_JSON" | jq -r ".[$i].template")
  SECTION_TITLE=$(echo "$LABEL_CONFIG_JSON" | jq -r ".[$i].section_title")

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