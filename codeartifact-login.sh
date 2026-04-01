#!/bin/bash
export UV_INDEX_STUDIO_FLEDGE_USERNAME=aws

refresh_codeartifact_token() {
    local TOKEN_FILE=~/.codeartifact-token
    local TOKEN_MAX_AGE_SECONDS=43200  # 12 hours
    local TOKEN_REFRESH_BUFFER=1800    # Refresh 30 minutes before expiry
    local EFFECTIVE_MAX_AGE=$((TOKEN_MAX_AGE_SECONDS - TOKEN_REFRESH_BUFFER))
    local FILE_MODE=0600  # Read/write for owner only

    # Function to get a new token
    get_new_token() {
        local NEW_TOKEN
        NEW_TOKEN=$(aws codeartifact get-authorization-token \
            --domain studio-fledge \
            --domain-owner 491085412041 \
            --region eu-west-1 \
            --query authorizationToken \
            --output text 2>&1)

        if [ $? -eq 0 ] && [ -n "$NEW_TOKEN" ] && [[ "$NEW_TOKEN" != *"error"* ]]; then
            echo "$NEW_TOKEN" > "$TOKEN_FILE"
            chmod "$FILE_MODE" "$TOKEN_FILE"
            echo "✅ CodeArtifact token refreshed (expires in 12h)"
            return 0
        else
            echo "Unable to fetch CodeArtifact authorization token. Please check your AWS credentials and permissions."
            return 1
        fi
    }

    # Check if token file exists and is still valid
    if [ -f "$TOKEN_FILE" ]; then
        # Get file modification time in seconds since epoch
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            FILE_TIME=$(stat -f %m "$TOKEN_FILE")
        else
            # Linux
            FILE_TIME=$(stat -c %Y "$TOKEN_FILE")
        fi

        CURRENT_TIME=$(date +%s)
        AGE_SECONDS=$((CURRENT_TIME - FILE_TIME))
        TIME_REMAINING=$((TOKEN_MAX_AGE_SECONDS - AGE_SECONDS))

        if [ $AGE_SECONDS -ge $EFFECTIVE_MAX_AGE ]; then
            get_new_token || return 1
        else
            local HOURS_REMAINING=$((TIME_REMAINING / 3600))
            local MINUTES_REMAINING=$(((TIME_REMAINING % 3600) / 60))
            echo "✅ Using cached CodeArtifact token (expires in ${HOURS_REMAINING}h ${MINUTES_REMAINING}m)"
        fi
    else
        # Token file doesn't exist, fetch new token
        get_new_token || return 1
    fi

    # Read the token value and set variable
    if [ -f "$TOKEN_FILE" ]; then
        export UV_INDEX_STUDIO_FLEDGE_PASSWORD=$(cat "$TOKEN_FILE")
    else
        return 1
    fi
}

_project_uses_codeartifact() {
  [ -f pyproject.toml ] && grep -q "codeartifact" pyproject.toml
}

# Wrap uv with CodeArtifact token refresh, chaining any existing wrapper (e.g. safe-chain)
if typeset -f uv > /dev/null 2>&1; then
  functions[_uv_delegate]=${functions[uv]}
else
  _uv_delegate() { command uv "$@"; }
fi

uv() {
  case "$1" in
    add|sync|install|lock)
      if _project_uses_codeartifact; then
        refresh_codeartifact_token || return 1
      fi
      ;;
  esac
  _uv_delegate "$@"
}
