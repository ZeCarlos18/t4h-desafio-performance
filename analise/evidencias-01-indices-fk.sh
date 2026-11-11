#!/usr/bin/env bash
# Evidências do experimento 01 (índices nas chaves estrangeiras), salvas em
# analise/saidas/. Só lê: não muda dados, índices nem configuração.
#
#   analise/evidencias-01-indices-fk.sh     (com o banco do commit 08f12ba no ar)
#
# Usa as mesmas consultas e parâmetros do diagnóstico (diagnostico/coletar.sh,
# arquivos 04c1 e 04c2), para comparar o plano antes e depois do índice.

set -euo pipefail
cd "$(dirname "$0")/.."

SAIDA=analise/saidas
ARQUIVO="$SAIDA/01-indices-fk-evidencias.txt"
mkdir -p "$SAIDA"

CLIENTE=12345
psql() { docker compose exec -T banco psql -U loja -d loja -X -v ON_ERROR_STOP=1 "$@"; }
PEDIDO="$(psql -At -c "SELECT id FROM pedidos WHERE cliente_id = $CLIENTE ORDER BY criado_em DESC, id DESC LIMIT 1;")"

{
  echo "# Experimento 01: evidências depois dos índices"
  echo "# gerado por analise/evidencias-01-indices-fk.sh em $(date '+%Y-%m-%d %H:%M:%S %z'), commit $(git rev-parse --short HEAD)"
  echo
  echo "## Índices das tabelas pedidos e itens_pedido e o espaço que ocupam"
  psql -c "SELECT indexrelid::regclass AS indice,
                  pg_size_pretty(pg_relation_size(indexrelid)) AS tamanho,
                  pg_relation_size(indexrelid) AS bytes
           FROM pg_index
           WHERE indrelid IN ('pedidos'::regclass, 'itens_pedido'::regclass)
           ORDER BY 1::text;"
  psql -c "SELECT pg_size_pretty(pg_database_size('loja')) AS tamanho_do_banco;"
  echo
  echo "## GET /clientes/$CLIENTE/pedidos: consulta dos pedidos (antes: diagnostico/saidas/04c1)"
  psql -c "EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM pedidos WHERE cliente_id = $CLIENTE ORDER BY criado_em DESC, id DESC;"
  echo
  echo "## GET /clientes/$CLIENTE/pedidos: consulta dos itens, pedido $PEDIDO (antes: diagnostico/saidas/04c2)"
  psql -c "EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM itens_pedido WHERE pedido_id = $PEDIDO ORDER BY id;"
} > "$ARQUIVO"
echo "salvo $ARQUIVO"
