#!/usr/bin/env bash
set -euo pipefail

STATS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATS_DERIVED_DATA="${MAC_DERIVED_DATA:-$STATS_ROOT/build/DeveloperWorkflow/macOS}"
STATS_PRODUCTS="$STATS_DERIVED_DATA/Build/Products/Debug"
STATS_OUTPUT="$STATS_ROOT/build/DeveloperWorkflow/ListeningStatsSmoke"

if [[ ! -d "$STATS_PRODUCTS/PrimuseKit.framework" ]]; then
    echo "Build PrimuseMac Debug in $STATS_DERIVED_DATA before running this check." >&2
    exit 1
fi
mkdir -p "$STATS_OUTPUT"
# Whole-module compilation lets the harness seed the view's private snapshot
# without adding test-only entry points to the application.
xcrun swiftc -swift-version 6 -D DEBUG -whole-module-optimization -Xfrontend -disable-access-control \
    -I "$STATS_PRODUCTS" \
    -I "$STATS_DERIVED_DATA/SourcePackages/checkouts/GRDB.swift/Sources/GRDBSQLite" \
    -F "$STATS_PRODUCTS" -framework PrimuseKit \
    -Xlinker -rpath -Xlinker "$STATS_PRODUCTS" \
    "$STATS_ROOT/Primuse/Views/Settings/ListeningStatsView.swift" \
    "$STATS_ROOT/Primuse/Views/Components/EmptyStateView.swift" \
    "$STATS_ROOT/scripts/ListeningStatsRenderingSmoke.swift" \
    -o "$STATS_OUTPUT/listening-stats-smoke"

"$STATS_OUTPUT/listening-stats-smoke" "$@"
