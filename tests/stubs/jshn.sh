# Минимальный стаб jshn.sh для тестов rpcd-плагина
json_init() { JSHN_OBJ=""; }
json_add_object() { JSHN_OBJ="$JSHN_OBJ\"$1\": {},"; }
json_add_string() { JSHN_OBJ="$JSHN_OBJ\"$1\": \"$2\","; }
json_close_object() { :; }
json_dump() { printf '{%s}\n' "$(echo "$JSHN_OBJ" | sed 's/,$//')"; }
json_load() { :; }
json_get_var() { eval "$1="; }
