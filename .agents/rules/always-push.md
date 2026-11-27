## Always Push to GitHub After Completing Tasks

After completing any code or file changes in this project, always commit and push the changes to GitHub automatically without asking for confirmation—unless the user explicitly says not to push or a pre-push check fails.

### Required Workflow
1. **Verify**: Run relevant tests (`flutter test ...`) and static analysis (`flutter analyze ...`) and confirm they pass.
2. **Follow the `push` skill**: Use `.agents/skills/push/SKILL.md` to inspect local changes, scan for secrets, generate a conventional commit message, commit, and push to the remote repository.
3. **Never push broken or unverified code**: If tests, analysis, or secret scans fail, fix the issue or report the blocker instead of pushing.
