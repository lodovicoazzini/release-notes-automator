# 🚀 Release Notes Automator

> **Automated, label-driven, and cross-repository GitHub Release Notes builder using closed issues from milestones.**

---

## ✨ Overview

**Release Notes Automator** is a GitHub Action that:
- Collects all **closed issues assigned to a milestone matching your release tag** (e.g. `v1.2.3`).
- Supports **cross-repository workflows** (issues from Repository B, releases in Repository A).
- Groups issues by labels (`feature`, `bug`, etc.) in configurable **sections with customizable templates**.
- Updates the **release body of the GitHub Release in your repository (Repo A)** automatically.
- Supports **draft, pre-release, publish, and edit** release events.

---

## 🎯 Use cases

✅ Automate release notes generation directly from issues  
✅ Ensure consistent and well-formatted changelogs  
✅ Support multiple repositories workflows (issues managed separately from code/releases)

---

## ⚙ Inputs

| Input               | Description                                                          | Required | Default              |
|---------------------|----------------------------------------------------------------------|----------|----------------------|
| `repo`              | Repository to fetch issues from (`owner/repo`). Defaults to current repository. | No       | Current repository   |
| `label_config`      | JSON array defining labels, templates, and section titles. See example below. | Yes      | -                    |
| `milestone_version` | Milestone name to match. Defaults to release tag (`v1.2.3`).        | No       | Tag name with `v`    |

---

## 🔐 Required environment variables

| Variable                    | Description                                                   | Required if                        |
|-----------------------------|---------------------------------------------------------------|------------------------------------|
| `ISSUES_REPOSITORY_TOKEN`   | Token with `read:issues` access to issues repository (Repo B) | Using external issues repository   |
| `GITHUB_TOKEN`              | GitHub Actions default token (auto-injected) with `write:contents` permission | Always                             |

---

## 📋 Example workflow

```yaml
name: Generate Custom Issue Changelog

on:
  release:
    types:
      - published
      - edited
      - prereleased

jobs:
  build_changelog:
    runs-on: ubuntu-latest
    steps:
      - name: Run release-notes-automator
        uses: your-org/release-notes-automator@v1
        with:
          repo: 'lodovicoazzini/set-saver'
          label_config: |
            [
              {
                "label": "feature",
                "template": "- 🚀 $TITLE",
                "section_title": "Features"
              },
              {
                "label": "bug",
                "template": "- 🐛 $TITLE",
                "section_title": "Bug Fixes"
              }
            ]
        env:
          ISSUES_REPOSITORY_TOKEN: ${{ secrets.LODOVICOAZZINI_SETSAVER_READ_ISSUES }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}