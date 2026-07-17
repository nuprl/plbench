# source scripts/claude-oauth.sh to run tasks with your Claude Code account,
# and not API credits.

unset ANTHROPIC_API_KEY

if ! claude auth status --json |
    jq -e '.loggedIn and (.authMethod == "claude.ai" or .authMethod == "oauth_token")'; then
    echo "Run 'claude login' before sourcing this script."
    return 1
fi

# Refresh an expired OAuth token.
if ! jq -e '.claudeAiOauth.expiresAt / 1000 > now' "${HOME}/.claude/.credentials.json"; then
    claude -p --model haiku --max-turns 1 'Reply with exactly OK.' || return 1
fi

# Configure Harbor's Claude Code adapter to use OAuth.
export CLAUDE_CODE_OAUTH_TOKEN="$(jq -er '.claudeAiOauth.accessToken' "${HOME}/.claude/.credentials.json")"
export CLAUDE_FORCE_OAUTH=1

echo "You can now do this:"
echo "    harbor run -p TASK_PATH -a claude-code -m anthropic/claude-sonnet-5 --ak reasoning_effort=high"
