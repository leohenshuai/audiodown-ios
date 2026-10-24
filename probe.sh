#!/bin/sh
# AudioDown 接口探测：逐个尝试认证方式，命中就打印出来
# 用法：AUDIODOWN_TOKEN=xxx sh probe.sh
# 或：sh probe.sh <token>
B="${AUDIODOWN_BASE:-https://audio.959935291.xyz:899}"
T="${1:-$AUDIODOWN_TOKEN}"
if [ -z "$T" ]; then echo "缺少 token"; exit 1; fi

PATHS="/api/me /api/books /api/v1/me /api/health /api/user"

try() { # $1=label $2...=curl args
  label="$1"; shift
  for p in $PATHS; do
    code=$(curl -sk -m 8 -o /tmp/pd_body -w '%{http_code}' "$@" "$B$p")
    if [ "$code" = "200" ]; then
      echo "✅ 命中: $label  ->  $p"
      head -c 600 /tmp/pd_body; echo
      echo "$label|$p" >> /tmp/pd_hit.txt
      return 0
    fi
  done
  printf '  %-34s %s\n' "$label" "未通过"
}

echo "base=$B token长度=${#T}"
try "Authorization: Bearer"   -H "Authorization: Bearer $T"
try "Authorization: Token"    -H "Authorization: Token $T"
try "Authorization: 裸token"  -H "Authorization: $T"
try "Authorization: ApiKey"   -H "Authorization: ApiKey $T"
try "X-Api-Key"               -H "X-Api-Key: $T"
try "X-API-KEY"               -H "X-API-KEY: $T"
try "X-Token"                 -H "X-Token: $T"
try "X-Access-Token"          -H "X-Access-Token: $T"
try "X-Auth-Token"            -H "X-Auth-Token: $T"
try "token 请求头"            -H "token: $T"
try "Cookie: token"           -b "token=$T"
try "Cookie: session"         -b "session=$T"
try "query ?token="           -G --data-urlencode "token=$T"
try "query ?api_key="         -G --data-urlencode "api_key=$T"
try "Basic admin:token"       -u "admin:$T"

echo
if [ -f /tmp/pd_hit.txt ]; then
  echo "=== 命中汇总 ==="; cat /tmp/pd_hit.txt
else
  echo "全部未通过。请向发 token 的人要一份示例 curl。"
fi
