# Single source of truth for the data location. Task 3 gate selected the
# extension-container fallback. Tests set USAGE_DIR_OVERRIDE to a sandbox.
USAGE_DIR="${USAGE_DIR_OVERRIDE:-$HOME/Library/Containers/com.mirabilia.MacUsageWidget.UsageWidget/Data/Library/Application Support/MacUsageWidget}"
USAGE_FILE="$USAGE_DIR/claude-code.json"
