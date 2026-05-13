#!/usr/bin/env bash
# validate_step2.sh — verify the Dockerfile no longer contains a build-time
# yolo export, and that entrypoint.sh exists with the right shebang.
# Exits 0 if all checks pass, 1 otherwise.
set -e

echo "=== Step 2 validator: Dockerfile refactored ==="

# 1. entrypoint.sh exists and is executable
[ -x entrypoint.sh ] || { echo "FAIL: entrypoint.sh missing or not executable"; exit 1; }
echo "PASS: entrypoint.sh present + executable"

# 2. entrypoint has the required shebang
head -1 entrypoint.sh | grep -q '^#!/usr/bin/env bash' \
    || { echo "FAIL: entrypoint.sh missing shebang"; exit 1; }
echo "PASS: shebang OK"

# 3. Dockerfile.ci has an ENTRYPOINT pointing at it
grep -q 'ENTRYPOINT.*entrypoint.sh' Dockerfile.ci \
    || { echo "FAIL: Dockerfile.ci does not ENTRYPOINT entrypoint.sh"; exit 1; }
echo "PASS: Dockerfile.ci wires ENTRYPOINT"

# 4. Dockerfile no longer has a build-time engine compile.
#    A bare grep (no -q) so we can show the offending line in the FAIL message.
if BAD=$(grep -nE "RUN.*format=['\"]?engine['\"]?" Dockerfile.ci); then
    echo "FAIL: Dockerfile.ci still has a RUN line that compiles the engine:"
    echo "      $BAD"
    echo "      Move that step into entrypoint.sh per Step 2.1."
    exit 1
fi
echo "PASS: no build-time engine compile in Dockerfile.ci"

echo "=== Step 2 PASS ==="
