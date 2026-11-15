#!/usr/bin/env bash
# Evidências do experimento 06 (índice em criado_em::date), salvas em
# analise/saidas/. Só lê: não muda dados, índices nem configuração.
#
#   analise/evidencias-06-indice-data.sh     (com o banco do commit 31a5875 no ar)
#
# Usa a mesma consulta e o mesmo período do diagnóstico (diagnostico/coletar.sh,
# arquivo 04f). A consulta roda duas vezes: a primeira pode ler do disco e a
# segunda mostra o caso com os dados já em memória, como sob carga.

set -euo pipefail
cd "$(dirname "$0")/.."

SAIDA=analise/saidas
ARQUIVO="$SAIDA/06-indice-data-evidencias.txt"
mkdir -p "$SAIDA"

INICIO=2024-06-01
FIM=2024-06-07
psql() { docker compose exec -T banco psql -U loja -d loja -X -v ON_ERROR_STOP=1 "$@"; }
CONSULTA="SELECT p.id AS pedido_id, p.criado_em, p.observacoes, i.quantidade, i.preco_unitario_centavos
     FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id
    WHERE p.criado_em::date BETWEEN '$INICIO' AND '$FIM' AND p.status <> 'cancelado';"

{
  echo "# Experimento 06: evidências depois do índice em criado_em::date"
  echo "# gerado por analise/evidencias-06-indice-data.sh em $(date '+%Y-%m-%d %H:%M:%S %z'), commit $(git rev-parse --short HEAD)"
  echo
  echo "## A conversão timestamp -> date é imutável (provolatile = i), requisito para índice de expressão"
  psql -c "SELECT p.proname, p.provolatile FROM pg_cast c JOIN pg_proc p ON p.oid = c.castfunc
           WHERE c.castsource = 'timestamp'::regtype AND c.casttarget = 'date'::regtype;"
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
  echo "## GET /relatorios/vendas-por-dia?inicio=$INICIO&fim=$FIM, 1ª execução (antes: diagnostico/saidas/04f-explain-vendas-por-dia.txt)"
  echo "$CONSULTA"
  psql -c "EXPLAIN (ANALYZE, BUFFERS) $CONSULTA"
  echo
  echo "## A mesma consulta, 2ª execução (dados já em memória)"
  psql -c "EXPLAIN (ANALYZE, BUFFERS) $CONSULTA"
} > "$ARQUIVO"
echo "salvo $ARQUIVO"
