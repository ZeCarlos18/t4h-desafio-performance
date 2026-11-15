#!/usr/bin/env bash
# Mede o log que a API escreveu desde que o container subiu: linhas, bytes e
# bytes por linha. Só lê. Uso: analise/log-por-requisicao.sh <rotulo>
# Salva em analise/saidas/<rotulo>-log.txt.
set -euo pipefail
cd "$(dirname "$0")/.."
ROTULO="${1:?informe o rótulo}"
SAIDA=analise/saidas
mkdir -p "$SAIDA"
ARQUIVO="$SAIDA/${ROTULO}-log.txt"
log="$(docker compose logs --no-log-prefix api)"
linhas="$(printf '%s\n' "$log" | grep -c '"metodo"' || true)"
bytes="$(printf '%s\n' "$log" | grep '"metodo"' | wc -c)"
{
  echo "# $ROTULO: log da API desde que o container subiu"
  echo "# gerado por analise/log-por-requisicao.sh em $(date '+%Y-%m-%d %H:%M:%S %z'), commit $(git rev-parse --short HEAD)"
  echo "# container iniciado em: $(docker inspect --format '{{.State.StartedAt}}' "$(docker compose ps -q api)")"
  echo
  echo "linhas de requisição: $linhas"
  echo "bytes dessas linhas:  $bytes"
  awk -v b="$bytes" -v l="$linhas" 'BEGIN { if (l > 0) printf "bytes por requisição (média): %.1f\n", b / l }'
  echo
  echo "Maior linha (bytes) e os primeiros 300 caracteres dela:"
  printf '%s\n' "$log" | grep '"metodo"' | awk '{ if (length($0) > max) { max = length($0); linha = $0 } } END { print "  " max " bytes"; print "  " substr(linha, 1, 300) }'
} > "$ARQUIVO"
echo "salvo $ARQUIVO"
