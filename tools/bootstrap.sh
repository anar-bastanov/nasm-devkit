#!/bin/sh

set -eu

usage() {
  echo "Usage: $0 <ProjectName> [ExecutableName]" >&2
  exit 2
}

case "$#" in
  1) PROJECT=$1; EXECUTABLE=$1 ;;
  2) PROJECT=$1; EXECUTABLE=$2 ;;
  *) usage ;;
esac

FILE="CMakeLists.txt"

if [ ! -f "$FILE" ]; then
  echo "Error: $FILE not found." >&2
  exit 3
fi

proj_head='set([ 	]*PROJECT_NAME_VAR'
exec_head='set([ 	]*EXECUTABLE_NAME_VAR'

pcnt=$(grep -c "$proj_head" "$FILE" || true)
if [ "$pcnt" -ne 1 ]; then
  echo "Error: expected exactly 1 PROJECT_NAME_VAR line, found $pcnt." >&2
  exit 6
fi

ecnt=$(grep -c "$exec_head" "$FILE" || true)
if [ "$ecnt" -ne 1 ]; then
  echo "Error: expected exactly 1 EXECUTABLE_NAME_VAR line, found $ecnt." >&2
  exit 6
fi

tmp=$(mktemp)
sed \
  -e "s#set([ 	]*PROJECT_NAME_VAR.*)#set(PROJECT_NAME_VAR \"$PROJECT\")#g" \
  -e "s#set([ 	]*EXECUTABLE_NAME_VAR.*)#set(EXECUTABLE_NAME_VAR \"$EXECUTABLE\")#g" \
  "$FILE" > "$tmp"
mv "$tmp" "$FILE"

echo "Project name set to: $PROJECT"
echo "Executable name set to: $EXECUTABLE"
