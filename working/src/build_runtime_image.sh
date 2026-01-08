#!/bin/bash

set -eou pipefail

cat <<'EOF' >&2
Runtime container builds are no longer used.
Use ./build_binary.sh to build and install the compiled binary.
EOF
exit 1
