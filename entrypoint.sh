#!/bin/bash
set -e

REPO="${1:-$GITHUB_REPOSITORY}"
LABEL_CONFIG_JSON=$2
MILESTONE_VERSION=$3

# Use the tag name directly with 'v' prefix if milestone version not explicitly passed
if [ -z "$MILESTONE_VERSION" ]; then
  MILESTONE_VERSION="${GITHUB_REF#refs/tags/}"
fi

echo "🔗 Issues will be fetched from: $REPO"
echo "🏷 Milestone version: $MILESTONE_VERSION"
echo "⚙ Label configuration: $LABEL_CONFIG_JSON"

# -------------------------
# Authenticate for Issues Repository (Repo B)
# -------------------------
if [ -n "$ISSUES_REPOSITORY_TOKEN" ]; then
  echo "$ISSUES_REPOSITORY_TOKEN" | gh auth login --with-token
else
  echo "$GITHUB_TOKEN" | gh auth login --with-token
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
# Re-authenticate for Release Repository (Repo A)
# -------------------------
echo "$GITHUB_TOKEN" | gh auth login --with-token

# -------------------------
# Update release body in Repo A
# -------------------------
echo "🔗 Updating release body for tag $MILESTONE_VERSION in $GITHUB_REPOSITORY..."
gh release edit "$MILESTONE_VERSION" --repo "$GITHUB_REPOSITORY" --notes-file "$CHANGELOG_FILE"

echo "🎉 Release body successfully updated!"