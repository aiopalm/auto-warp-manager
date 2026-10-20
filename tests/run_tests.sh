#!/bin/sh
# Запускает все кейсы; exit 1 при любом провале
cd "$(dirname "$0")"
TOTAL=0
FAILED=0
for t in case_*.sh; do
	[ -f "$t" ] || continue
	TOTAL=$((TOTAL+1))
	echo "== $t"
	if sh "$t"; then :; else FAILED=$((FAILED+1)); echo "!! $t FAILED"; fi
done
if [ -f case_07_view.py ]; then
	TOTAL=$((TOTAL+1))
	echo "== case_07_view.py"
	if python3 case_07_view.py; then :; else FAILED=$((FAILED+1)); echo "!! case_07_view.py FAILED"; fi
fi
echo "===== suites: $TOTAL, failed: $FAILED"
[ "$FAILED" -eq 0 ]
