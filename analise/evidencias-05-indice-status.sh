#!/usr/bin/env bash
# Evidências do experimento 05 (índice (status, criado_em DESC, id DESC)),
# salvas em analise/saidas/. Só lê: não muda dados, índices nem configuração.
#
#   analise/evidencias-05-indice-status.sh     (com o banco do commit 5039717 no ar)
#
# Usa as mesmas consultas e parâmetros do diagnóstico (diagnostico/coletar.sh,
# arquivos 04d1 e 04d2), para comparar o plano antes e depois do índice.

set -euo pipefail
cd "$(dirname "$0")/.."

SAIDA=analise/saidas
ARQUIVO="$SAIDA/05-indice-status-evidencias.txt"
mkdir -p "$SAIDA"

STATUS=pago
PAGINA=500
psql() { docker compose exec -T banco psql -U loja -d loja -X -v ON_ERROR_STOP=1 "$@"; }

{
  echo "# Experimento 05: evidências depois do índice (status, criado_em DESC, id DESC)"
  echo "# gerado por analise/evidencias-05-indice-status.sh em $(date '+%Y-%m-%d %H:%M:%S %z'), commit $(git rev-parse --short HEAD)"
  echo
  echo "## Índices da tabela pedidos e o espaço que ocupam"
  psql -c "SELECT indexrelid::regclass AS indice,
                  pg_size_pretty(pg_relation_size(indexrelid)) AS tamanho,
                  pg_relation_size(indexrelid) AS bytes
           FROM pg_index
           WHERE indrelid = 'pedidos'::regclass
           ORDER BY 1::text;"
  psql -c "SELECT pg_size_pretty(pg_database_size('loja')) AS tamanho_do_banco;"
  echo
  echo "## GET /pedidos?status=$STATUS&pagina=$PAGINA: contagem (antes: diagnostico/saidas/04d1-explain-pedidos-por-status-contagem.txt)"
  psql -c "EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) AS total FROM pedidos WHERE status = '$STATUS';"
  echo
  echo "## GET /pedidos?status=$STATUS&pagina=$PAGINA: página (antes: diagnostico/saidas/04d2-explain-pedidos-por-status-pagina.txt)"
  psql -c "EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM pedidos WHERE status = '$STATUS' ORDER BY criado_em DESC, id DESC LIMIT 20 OFFSET $(( (PAGINA - 1) * 20 ));"
  echo
  echo "## A última página que a carga sorteia (pagina=1000, OFFSET 19980), para ver o custo do OFFSET"
  psql -c "EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM pedidos WHERE status = '$STATUS' ORDER BY criado_em DESC, id DESC LIMIT 20 OFFSET 19980;"
} > "$ARQUIVO"
echo "salvo $ARQUIVO"
