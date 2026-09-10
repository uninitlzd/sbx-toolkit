#!/usr/bin/env bash
# install.sh — installs sbx-start and sbx-setup from GitHub
# Usage: curl -fsSL https://raw.githubusercontent.com/your-org/sbx-toolkit/main/install.sh | bash
set -euo pipefail

REPO="uninitlzd/sbx-toolkit"
BRANCH="main"
BINARIES=("sbx-start" "sbx-setup")
TEMPLATE_FILES=(
	"templates/README.md"
	"templates/base/Dockerfile"
	"templates/mise/Dockerfile"
)
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/sbx-toolkit"

# ── resolve install dir ───────────────────────────────────────────────────────

if echo "$PATH" | grep -q "$HOME/bin"; then
	INSTALL_DIR="$HOME/bin"
elif echo "$PATH" | grep -q "$HOME/.local/bin"; then
	INSTALL_DIR="$HOME/.local/bin"
elif [[ -w "/usr/local/bin" ]]; then
	INSTALL_DIR="/usr/local/bin"
else
	INSTALL_DIR="$HOME/.local/bin"
fi

mkdir -p "$INSTALL_DIR"

# ── check dependencies ────────────────────────────────────────────────────────

command -v curl >/dev/null 2>&1 || {
	echo "ERROR: curl is required." >&2
	exit 1
}

# ── install binaries ──────────────────────────────────────────────────────────

for binary in "${BINARIES[@]}"; do
	raw_url="https://raw.githubusercontent.com/${REPO}/${BRANCH}/${binary}"
	install_path="$INSTALL_DIR/$binary"

	echo "→ Downloading $binary"
	if ! curl -fsSL "$raw_url" -o "$install_path"; then
		echo "ERROR: Failed to install $binary to $install_path" >&2
		echo "       Choose a writable directory in PATH or rerun with elevated permissions." >&2
		exit 1
	fi

	chmod +x "$install_path"
	echo "✓ Installed to $install_path"
done

# ── install templates for sbx-setup ──────────────────────────────────────────

echo "→ Installing templates to $DATA_DIR/templates"
for template_file in "${TEMPLATE_FILES[@]}"; do
	target_path="$DATA_DIR/$template_file"
	target_dir="$(dirname "$target_path")"
	url="https://raw.githubusercontent.com/${REPO}/${BRANCH}/${template_file}"

	mkdir -p "$target_dir"
	if ! curl -fsSL "$url" -o "$target_path"; then
		echo "ERROR: Failed to download $template_file" >&2
		exit 1
	fi
done
echo "✓ Templates installed to $DATA_DIR/templates"

# ── verify ────────────────────────────────────────────────────────────────────

missing=()
for binary in "${BINARIES[@]}"; do
	if command -v "$binary" >/dev/null 2>&1; then
		echo "✓ $binary is on your PATH"
	else
		missing+=("$binary")
	fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
	echo ""
	echo "NOTE: Add $INSTALL_DIR to your PATH:"
	echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
	echo ""
fi

# ── set up CLAUDE_CODE_OAUTH_TOKEN in Keychain (macOS only) ───────────────────

if [[ "$(uname -s)" == "Darwin" ]]; then
	KEYCHAIN_SERVICE="claude-code-oauth-token"

	if security find-generic-password -a "$USER" -s "$KEYCHAIN_SERVICE" -w >/dev/null 2>&1; then
		echo ""
		echo "✓ CLAUDE_CODE_OAUTH_TOKEN already stored in Keychain"
	elif [[ -r /dev/tty ]]; then
		echo ""
		echo "No Claude Code OAuth token found in Keychain."
		echo "Generate one with: claude setup-token"
		printf "Paste token now to store it (leave blank to skip): "
		# `if read ...; then` (not a bare `read`) so a failed/unconfigured
		# /dev/tty (CI, docker exec without -it, etc.) degrades to the
		# skip message below instead of killing the whole install under
		# set -e.
		if read -rs TOKEN </dev/tty 2>/dev/null; then
			echo
			if [[ -n "$TOKEN" ]]; then
				security add-generic-password -a "$USER" -s "$KEYCHAIN_SERVICE" -w "$TOKEN" -U
				echo "✓ Stored in Keychain"
			else
				echo "→ Skipped. Store later with:"
				echo "  security add-generic-password -a \"\$USER\" -s $KEYCHAIN_SERVICE -w \"<token>\" -U"
			fi
			unset TOKEN
		else
			echo ""
			echo "→ Couldn't read from terminal. Store later with:"
			echo "  security add-generic-password -a \"\$USER\" -s $KEYCHAIN_SERVICE -w \"<token>\" -U"
		fi
	else
		echo ""
		echo "NOTE: no terminal attached — couldn't prompt for a token."
		echo "      Store one later with:"
		echo "      security add-generic-password -a \"\$USER\" -s $KEYCHAIN_SERVICE -w \"<token>\" -U"
	fi

	# ── add sbx-start wrapper to shell rc (idempotent) ────────────────────────────

	WRAPPER_MARKER="# sbx-toolkit: pull CLAUDE_CODE_OAUTH_TOKEN from Keychain fresh on every"
	case "${SHELL:-}" in
	*/zsh) RC_FILE="$HOME/.zshrc" ;;
	*/bash) RC_FILE="$HOME/.bashrc" ;;
	*) RC_FILE="" ;;
	esac

	if [[ -n "$RC_FILE" ]]; then
		if [[ -f "$RC_FILE" ]] && grep -qF "$WRAPPER_MARKER" "$RC_FILE"; then
			echo "✓ sbx-start Keychain wrapper already present in $RC_FILE"
		else
			cat >>"$RC_FILE" <<RCEOF

$WRAPPER_MARKER
# sbx-start call, scoped to that one invocation only — never persisted.
sbx-start() {
  CLAUDE_CODE_OAUTH_TOKEN="\$(security find-generic-password -a "\$USER" -s "$KEYCHAIN_SERVICE" -w 2>/dev/null)" \\
    command sbx-start "\$@"
}
RCEOF
			echo "✓ Added sbx-start Keychain wrapper to $RC_FILE (restart your shell or: source $RC_FILE)"
		fi
	else
		echo "NOTE: unrecognized \$SHELL ('${SHELL:-unset}') — skipped adding the sbx-start Keychain wrapper."
		echo "      See https://github.com/${REPO}#env-vars to add it manually."
	fi
fi

echo ""
echo "Next steps:"
echo "  1. Run: sbx-setup --config ~/.claude"
echo "  2. Run: sbx-start"
echo ""
echo "Templates location: $DATA_DIR/templates"
echo ""
echo "Full docs: https://github.com/${REPO}"
