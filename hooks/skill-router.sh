#!/usr/bin/env bash
# UserPromptSubmit hook: routes a prompt to the rstack skill that covers it.
# A hook cannot invoke a skill, so it injects the instruction as context.
# Prints nothing (and so changes nothing) when no rule matches.
set -uo pipefail

prompt="$(jq -r '.prompt // empty' 2>/dev/null)" || exit 0
[ -n "$prompt" ] || exit 0

# Explicit slash commands and prompts that already name a skill route themselves.
case "$prompt" in /*) exit 0 ;; esac
printf '%s' "$prompt" | grep -Eiq 'rstack-' && exit 0

has() { printf '%s' "$prompt" | grep -Eiq -- "$1"; }

skill=""
strict=1
if has 'github\.com/[^ ]+/pull/[0-9]+' \
  || has '\b(review|revisa|rev[ií]same|revisar|revisi[oó]n|rev[ií]salo)\b.*\b(pr|prs|pull request)\b' \
  || has '\b(pr|pull request)\b.*\b(review|revisa|rev[ií]same|revisar|revisi[oó]n)\b'; then
  skill="rstack-review"
elif has '\b(bug|bugs|debug|debuggea|depura|investiga|investigar|incidencia|regresi[oó]n|regression)\b' \
  || has '\b(no funciona|no va|est[aá] roto|falla|fallando|peta|petando)\b' \
  || has 'por ?qu[eé] (no|falla|sale|se|est[aá]|da)\b' \
  || has '\bwhy (is|does|did|are|do)\b.*\b(fail|failing|broken|wrong|not)\b'; then
  skill="rstack-investigate"
elif has '\b(implementa|implementar|implementemos|nueva feature|new feature|nueva funcionalidad)\b' \
  || has '\b(quiero|necesito|vamos a|hay que) (hacer|a[nñ]adir|montar|construir|crear|implementar)\b' \
  || has '\b(implement|build|add support for)\b'; then
  skill="rstack-plan"
  strict=0
fi

[ -n "$skill" ] || exit 0

if [ "$strict" = 1 ]; then
  msg="[rstack router] This prompt matches the \`$skill\` skill. Invoke it with the Skill tool BEFORE any other tool call and follow it to the end. Do not substitute another review/debugging approach or do the work by hand. Skip it only if the prompt is clearly not that kind of task, and say so in one line."
else
  msg="[rstack router] This prompt looks like feature work. If it is non-trivial (more than a small, fully specified change), invoke the \`$skill\` skill with the Skill tool BEFORE reading or editing code. If it is trivial or it continues work already planned in this conversation, carry on without it."
fi

jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$m}}'
