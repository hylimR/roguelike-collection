#!/bin/sh
# usage: sh tools/trace/run.sh key [key ...]   one Codex trace per build/trace/<key>/ job (python tools/trace/trace.py
# jobs first), at most 5 at a time; each writes model.json there and prints its final scores
cd "$(dirname "$0")/../../build/trace" || exit 1
for key in "$@"; do
	(
		cd "$key" && codex exec --skip-git-repo-check -C . -s workspace-write -i cell.png -o last.txt - < prompt.txt > log.txt 2>&1
		echo "$key done: $(tail -1 last.txt 2>/dev/null)"
	) &
	while [ "$(jobs -r | wc -l)" -ge 5 ]; do sleep 5; done
done
wait
