#!/usr/bin/env bash
# Evidências do experimento 07 (view materializada receita_por_produto),
# salvas em analise/saidas/. Só lê: não muda dados, índices nem configuração.
#
#   analise/evidencias-07-view-top-produtos.sh     (com o banco do commit 5b5bfff no ar)
#
# Compara a consulta nova da rota (lendo da view) com a consulta antiga
# (diagnostico/saidas/04g-explain-top-produtos.txt), e mostra quanto custa
# atualizar a view, que é o preço dessa troca.

set -euo pipefail
cd "$(dirname "$0")/.."

SAIDA=analise/saidas
ARQUIVO="$SAIDA/07-view-top-produtos-evidencias.txt"
mkdir -p "$SAIDA"

psql() { docker compose exec -T banco psql -U loja -d loja -X -v ON_ERROR_STOP=1 "$@"; }

{
  echo "# Experimento 07: evidências depois da view materializada receita_por_produto"
  echo "# gerado por analise/evidencias-07-view-top-produtos.sh em $(date '+%Y-%m-%d %H:%M:%S %z'), commit $(git rev-parse --short HEAD)"
  echo
  echo "## Tamanho da view, do índice dela e do banco"
  psql -c "SELECT c.relname AS objeto, c.relkind AS tipo, pg_size_pretty(pg_relation_size(c.oid)) AS tamanho,
                  pg_relation_size(c.oid) AS bytes
           FROM pg_class c
           WHERE c.relname IN ('receita_por_produto', 'receita_por_produto_receita_id_idx')
           ORDER BY 1;"
  psql -c "SELECT count(*) AS linhas_na_view FROM receita_por_produto;"
  psql -c "SELECT pg_size_pretty(pg_database_size('loja')) AS tamanho_do_banco;"
  echo
  echo "## GET /relatorios/top-produtos?limite=10: consulta nova, lendo da view"
  psql -c "EXPLAIN (ANALYZE, BUFFERS) SELECT id, nome, categoria, unidades, receita_centavos
             FROM receita_por_produto ORDER BY receita_centavos DESC, id LIMIT 10;"
  echo
  echo "## O mesmo resultado pela consulta antiga, para conferir que é idêntico (EXCEPT nos dois sentidos deve dar 0 linhas)"
  psql -c "WITH antiga AS (
             SELECT pr.id, pr.nome, pr.categoria, sum(i.quantidade) AS unidades,
                    sum(i.quantidade * i.preco_unitario_centavos) AS receita_centavos
               FROM itens_pedido i JOIN pedidos p ON p.id = i.pedido_id JOIN produtos pr ON pr.id = i.produto_id
              WHERE p.status <> 'cancelado' GROUP BY pr.id, pr.nome, pr.categoria)
           SELECT (SELECT count(*) FROM (SELECT * FROM antiga EXCEPT SELECT * FROM receita_por_produto) a) AS so_na_antiga,
                  (SELECT count(*) FROM (SELECT * FROM receita_por_produto EXCEPT SELECT * FROM antiga) b) AS so_na_view;"
  echo
  echo "## Custo de atualizar a view (REFRESH), o preço de guardar o resultado pronto"
  echo "## Executado dentro de uma transação desfeita (ROLLBACK), para não alterar o banco medido"
  psql -c "\\timing on" -c "BEGIN;" -c "REFRESH MATERIALIZED VIEW receita_por_produto;" -c "ROLLBACK;"
} > "$ARQUIVO"
echo "salvo $ARQUIVO"
