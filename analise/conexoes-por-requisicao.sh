#!/usr/bin/env bash
# Conta as conexões que cada rota abre no banco, sem carga, com o mesmo método
# do diagnóstico (diagnostico/coletar.sh, arquivo 05), para comparar antes e
# depois de uma mudança. Só lê: não muda dados, índices nem configuração.
#
#   analise/conexoes-por-requisicao.sh <rotulo>     (com a aplicação no ar)
#
# Salva em analise/saidas/<rotulo>-conexoes.txt.

set -euo pipefail
cd "$(dirname "$0")/.."

ROTULO="${1:?informe o rótulo, ex.: 02-fim-n-mais-1}"
SAIDA=analise/saidas
ARQUIVO="$SAIDA/${ROTULO}-conexoes.txt"
mkdir -p "$SAIDA"

CLIENTE=12345
EMAIL=cliente12345@exemplo.com
STATUS=pago
PAGINA=500
TERMO=cadeira
INICIO=2024-06-01
FIM=2024-06-07
API=http://127.0.0.1:3000
REPETICOES=10

psql() { docker compose exec -T banco psql -U loja -d loja -X -v ON_ERROR_STOP=1 "$@"; }
sessoes() { psql -At -c "SELECT sessions FROM pg_stat_database WHERE datname = 'loja';"; }

{
  echo "# $ROTULO: conexões abertas por requisição, sem carga"
  echo "# gerado por analise/conexoes-por-requisicao.sh em $(date '+%Y-%m-%d %H:%M:%S %z'), commit $(git rev-parse --short HEAD)"
  echo
  echo "Método: diferença do contador sessions de pg_stat_database antes e depois de $REPETICOES requisições, dividida por $REPETICOES."
  echo "O contador também conta a própria leitura (1 sessão) e o healthcheck do compose (pg_isready a cada 5 s),"
  echo "então o valor por requisição pode passar um pouco do real. A linha 'controle' mostra esse ruído sem nenhuma requisição."
  echo "Antes da primeira mudança: diagnostico/saidas/05-conexoes-por-requisicao.txt."
  echo
  printf "%-62s %6s %12s %8s %13s %20s\n" "requisicao" "http" "tempo_medio_s" "bytes" "sessoes_total" "sessoes_por_requisicao"
  s0="$(sessoes)"; sleep 10; s1="$(sessoes)"
  printf "%-62s %6s %12s %8s %13s %20s\n" "controle: 10 s sem requisição" "-" "-" "-" "$(( s1 - s0 ))" "-"
  for caminho in \
    "/clientes/$CLIENTE" \
    "/clientes?email=$EMAIL" \
    "/clientes/$CLIENTE/pedidos" \
    "/pedidos?status=$STATUS&pagina=$PAGINA" \
    "/produtos/busca?q=$TERMO" \
    "/relatorios/vendas-por-dia?inicio=$INICIO&fim=$FIM" \
    "/relatorios/top-produtos?limite=10"; do
    s0="$(sessoes)"
    medidas="$(for _ in $(seq "$REPETICOES"); do
      curl -s -o /dev/null -w '%{http_code} %{time_total} %{size_download}\n' "$API$caminho"
    done)"
    sleep 2
    s1="$(sessoes)"
    read -r codigo _ bytes <<< "$(head -1 <<< "$medidas")"
    tempo="$(awk '{ soma += $2 } END { printf "%.4f", soma / NR }' <<< "$medidas")"
    printf "%-62s %6s %12s %8s %13s %20s\n" "GET $caminho" "$codigo" "$tempo" "$bytes" \
      "$(( s1 - s0 ))" "$(awk -v d="$(( s1 - s0 ))" -v n="$REPETICOES" 'BEGIN { printf "%.1f", d / n }')"
  done
} > "$ARQUIVO"
echo "salvo $ARQUIVO"
