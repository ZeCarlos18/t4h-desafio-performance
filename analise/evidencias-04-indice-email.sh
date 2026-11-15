#!/usr/bin/env bash
# Evidências do experimento 04 (índice em lower(email)), salvas em
# analise/saidas/. Só lê: não muda dados, índices nem configuração.
#
#   analise/evidencias-04-indice-email.sh     (com o banco do commit 00bd026 no ar)
#
# Usa a mesma consulta e o mesmo e-mail do diagnóstico (diagnostico/coletar.sh,
# arquivo 04b), para comparar o plano antes e depois do índice.

set -euo pipefail
cd "$(dirname "$0")/.."

SAIDA=analise/saidas
ARQUIVO="$SAIDA/04-indice-email-evidencias.txt"
mkdir -p "$SAIDA"

EMAIL=cliente12345@exemplo.com
psql() { docker compose exec -T banco psql -U loja -d loja -X -v ON_ERROR_STOP=1 "$@"; }

{
  echo "# Experimento 04: evidências depois do índice em lower(email)"
  echo "# gerado por analise/evidencias-04-indice-email.sh em $(date '+%Y-%m-%d %H:%M:%S %z'), commit $(git rev-parse --short HEAD)"
  echo
  echo "## Índices da tabela clientes e o espaço que ocupam"
  psql -c "SELECT indexrelid::regclass AS indice,
                  pg_size_pretty(pg_relation_size(indexrelid)) AS tamanho,
                  pg_relation_size(indexrelid) AS bytes
           FROM pg_index
           WHERE indrelid = 'clientes'::regclass
           ORDER BY 1::text;"
  psql -c "SELECT pg_size_pretty(pg_database_size('loja')) AS tamanho_do_banco;"
  echo
  echo "## GET /clientes?email=$EMAIL (antes: diagnostico/saidas/04b-explain-cliente-por-email.txt)"
  psql -c "EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM clientes WHERE lower(email) = lower('$EMAIL') ORDER BY id;"
  echo
  echo "## A mesma busca com o e-mail em maiúsculas (o contrato testa esse caso)"
  psql -c "EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM clientes WHERE lower(email) = lower('CLIENTE10@EXEMPLO.COM') ORDER BY id;"
} > "$ARQUIVO"
echo "salvo $ARQUIVO"
