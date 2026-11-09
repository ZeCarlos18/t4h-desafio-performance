#!/usr/bin/env bash
# Coleta as evidências do diagnóstico (etapa 02) e salva em diagnostico/saidas/.
# Só lê: não muda dados, índices nem configuração do banco.
#
#   diagnostico/coletar.sh        (com a aplicação no ar: docker compose up -d --build)
#
# Parâmetros fixos, no mesmo formato que o teste de carga sorteia (carga/teste-carga.js).

set -euo pipefail
cd "$(dirname "$0")/.."

SAIDA=diagnostico/saidas
mkdir -p "$SAIDA"

CLIENTE=12345
EMAIL=cliente12345@exemplo.com
STATUS=pago
PAGINA=500
TERMO=cadeira
INICIO=2024-06-01
FIM=2024-06-07
API=http://127.0.0.1:3000

psql() { docker compose exec -T banco psql -U loja -d loja -X -v ON_ERROR_STOP=1 "$@"; }

cabecalho() {
  echo "# $1"
  echo "# gerado por diagnostico/coletar.sh em $(date '+%Y-%m-%d %H:%M:%S %z'), commit $(git rev-parse --short HEAD)"
  echo
}

# Plano de execução real de uma consulta: EXPLAIN (ANALYZE, BUFFERS) executa a consulta e mostra
# o caminho escolhido, as linhas lidas, o tempo e as páginas lidas do cache (hit) ou do disco (read).
explicar() {
  local arquivo="$1" titulo="$2" sql="$3"
  {
    cabecalho "$titulo"
    echo "$sql"
    echo
    psql -c "EXPLAIN (ANALYZE, BUFFERS) $sql"
  } > "$SAIDA/$arquivo"
  echo "salvo $SAIDA/$arquivo"
}

echo "== 01: estrutura, tamanhos e índices"
{
  cabecalho "Estrutura das tabelas, tamanho em disco e índices existentes"
  psql -c "SELECT version();"
  psql -c "\d clientes" -c "\d produtos" -c "\d pedidos" -c "\d itens_pedido"
  psql -c "SELECT c.relname AS tabela, c.reltuples::bigint AS linhas_estimadas,
                  pg_size_pretty(pg_table_size(c.oid)) AS dados,
                  pg_size_pretty(pg_indexes_size(c.oid)) AS indices,
                  pg_size_pretty(pg_total_relation_size(c.oid)) AS total
             FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public' AND c.relkind = 'r'
            ORDER BY pg_total_relation_size(c.oid) DESC;"
  psql -c "SELECT tablename AS tabela, indexname AS indice, indexdef AS definicao
             FROM pg_indexes WHERE schemaname = 'public' ORDER BY tablename, indexname;"
  psql -c "SELECT pg_size_pretty(pg_database_size('loja')) AS tamanho_do_banco;"
} > "$SAIDA/01-estrutura-e-indices.txt"
echo "salvo $SAIDA/01-estrutura-e-indices.txt"

echo "== 02: configuração do PostgreSQL"
{
  cabecalho "Parâmetros do PostgreSQL em uso (source = default quer dizer valor de fábrica)"
  psql -c "SELECT name, setting, unit, source FROM pg_settings
            WHERE name IN ('max_connections','shared_buffers','effective_cache_size','work_mem',
                           'maintenance_work_mem','random_page_cost','effective_io_concurrency',
                           'max_parallel_workers_per_gather','jit','shared_preload_libraries')
            ORDER BY name;"
} > "$SAIDA/02-configuracao-postgres.txt"
echo "salvo $SAIDA/02-configuracao-postgres.txt"

echo "== 03: estatísticas acumuladas de acesso às tabelas"
{
  cabecalho "Leituras acumuladas desde a criação do banco (geração dos dados, contrato, medições e execuções anteriores deste script)"
  echo "seq_scan = leituras da tabela inteira; idx_scan = leituras por índice."
  echo
  psql -c "SELECT relname AS tabela, seq_scan, seq_tup_read AS linhas_lidas_em_seq_scan,
                  idx_scan, idx_tup_fetch AS linhas_lidas_por_indice
             FROM pg_stat_user_tables ORDER BY seq_tup_read DESC;"
  psql -c "SELECT datname, sessions AS sessoes_abertas, xact_commit AS transacoes,
                  blks_hit AS paginas_do_cache, blks_read AS paginas_do_disco,
                  round(100.0 * blks_hit / nullif(blks_hit + blks_read, 0), 2) AS pct_cache
             FROM pg_stat_database WHERE datname = 'loja';"
} > "$SAIDA/03-estatisticas-de-acesso.txt"
echo "salvo $SAIDA/03-estatisticas-de-acesso.txt"

echo "== 04: planos de execução das consultas de cada rota"
PEDIDO="$(psql -At -c "SELECT id FROM pedidos WHERE cliente_id = $CLIENTE ORDER BY criado_em DESC, id DESC LIMIT 1;")"
PRODUTO="$(psql -At -c "SELECT produto_id FROM itens_pedido WHERE pedido_id = $PEDIDO ORDER BY id LIMIT 1;")"

explicar 04a-explain-cliente.txt "GET /clientes/$CLIENTE" \
  "SELECT * FROM clientes WHERE id = $CLIENTE;"
explicar 04b-explain-cliente-por-email.txt "GET /clientes?email=$EMAIL" \
  "SELECT * FROM clientes WHERE lower(email) = lower('$EMAIL') ORDER BY id;"
explicar 04c1-explain-pedidos-do-cliente-pedidos.txt "GET /clientes/$CLIENTE/pedidos: consulta dos pedidos (1 vez por requisição)" \
  "SELECT * FROM pedidos WHERE cliente_id = $CLIENTE ORDER BY criado_em DESC, id DESC;"
explicar 04c2-explain-pedidos-do-cliente-itens.txt "GET /clientes/$CLIENTE/pedidos: consulta dos itens (1 vez POR PEDIDO), pedido $PEDIDO" \
  "SELECT * FROM itens_pedido WHERE pedido_id = $PEDIDO ORDER BY id;"
explicar 04c3-explain-pedidos-do-cliente-produto.txt "GET /clientes/$CLIENTE/pedidos: consulta do produto (1 vez POR ITEM), produto $PRODUTO" \
  "SELECT * FROM produtos WHERE id = $PRODUTO;"
explicar 04d1-explain-pedidos-por-status-contagem.txt "GET /pedidos?status=$STATUS&pagina=$PAGINA: contagem" \
  "SELECT count(*) AS total FROM pedidos WHERE status = '$STATUS';"
explicar 04d2-explain-pedidos-por-status-pagina.txt "GET /pedidos?status=$STATUS&pagina=$PAGINA: página (OFFSET $(( (PAGINA - 1) * 20 )))" \
  "SELECT * FROM pedidos WHERE status = '$STATUS' ORDER BY criado_em DESC, id DESC LIMIT 20 OFFSET $(( (PAGINA - 1) * 20 ));"
explicar 04e-explain-busca-produtos.txt "GET /produtos/busca?q=$TERMO" \
  "SELECT * FROM produtos WHERE nome ILIKE '%' || '$TERMO' || '%' ORDER BY nome, id LIMIT 20;"
explicar 04f-explain-vendas-por-dia.txt "GET /relatorios/vendas-por-dia?inicio=$INICIO&fim=$FIM" \
  "SELECT p.id AS pedido_id, p.criado_em, p.observacoes, i.quantidade, i.preco_unitario_centavos
     FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id
    WHERE p.criado_em::date BETWEEN '$INICIO' AND '$FIM' AND p.status <> 'cancelado';"
{
  echo
  echo "# Volume que essa consulta manda do banco para a API (a API só usa pedido_id, criado_em, quantidade e preço):"
  psql -c "SELECT count(*) AS linhas_enviadas,
                  pg_size_pretty(sum(octet_length(p.observacoes))::bigint) AS bytes_so_de_observacoes
             FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id
            WHERE p.criado_em::date BETWEEN '$INICIO' AND '$FIM' AND p.status <> 'cancelado';"
} >> "$SAIDA/04f-explain-vendas-por-dia.txt"
explicar 04g-explain-top-produtos.txt "GET /relatorios/top-produtos?limite=10" \
  "SELECT pr.id, pr.nome, pr.categoria, sum(i.quantidade) AS unidades,
          sum(i.quantidade * i.preco_unitario_centavos) AS receita_centavos
     FROM itens_pedido i JOIN pedidos p ON p.id = i.pedido_id JOIN produtos pr ON pr.id = i.produto_id
    WHERE p.status <> 'cancelado'
    GROUP BY pr.id, pr.nome, pr.categoria ORDER BY receita_centavos DESC, pr.id LIMIT 10;"

echo "== 05: conexões abertas por requisição, sem carga"
REPETICOES=10
sessoes() { psql -At -c "SELECT sessions FROM pg_stat_database WHERE datname = 'loja';"; }
{
  cabecalho "Sem carga: $REPETICOES requisições seguidas de cada rota, com tempo médio, tamanho da resposta e conexões abertas no banco"
  echo "Método: diferença do contador sessions de pg_stat_database antes e depois das $REPETICOES requisições, dividida por $REPETICOES."
  echo "O contador também conta a própria leitura (1 sessão) e o healthcheck do compose (pg_isready a cada 5 s),"
  echo "então o valor por requisição pode passar um pouco do real. A linha 'controle' mostra esse ruído sem nenhuma requisição."
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
  echo
  echo "Para conferir a conta da rota de pedidos do cliente (1 consulta do cliente + 1 dos pedidos + 1 por pedido + 1 por item):"
  psql -c "SELECT count(DISTINCT p.id) AS pedidos, count(i.id) AS itens,
                  2 + count(DISTINCT p.id) + count(i.id) AS consultas_esperadas
             FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id WHERE p.cliente_id = $CLIENTE;"
} > "$SAIDA/05-conexoes-por-requisicao.txt"
echo "salvo $SAIDA/05-conexoes-por-requisicao.txt"

echo "== 06: custo de abrir uma conexão por consulta (pgbench)"
REDE="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' "$(docker compose ps -q banco)")"
{
  cabecalho "pgbench: a mesma consulta da rota /clientes/:id, 1 cliente por 10 s, reaproveitando a conexão e abrindo uma nova a cada consulta (-C)"
  echo "Roda num container separado, na mesma rede da API, para não usar a CPU do container do banco."
  echo
  echo "--- reaproveitando a conexão ---"
  docker run --rm --network "$REDE" -e PGUSER=loja postgres:16.4 \
    sh -c 'echo "SELECT * FROM clientes WHERE id = 12345;" > /tmp/q.sql && pgbench -h banco -n -c 1 -T 10 -f /tmp/q.sql loja' 2>&1
  echo
  echo "--- uma conexão nova por consulta (-C), como faz api/src/db.js ---"
  docker run --rm --network "$REDE" -e PGUSER=loja postgres:16.4 \
    sh -c 'echo "SELECT * FROM clientes WHERE id = 12345;" > /tmp/q.sql && pgbench -h banco -n -C -c 1 -T 10 -f /tmp/q.sql loja' 2>&1
} > "$SAIDA/06-custo-de-conexao-pgbench.txt"
echo "salvo $SAIDA/06-custo-de-conexao-pgbench.txt"

echo "== 07: log da API"
{
  cabecalho "O que a API escreve no log a cada requisição (api/src/server.js registra o corpo inteiro da resposta)"
  echo "Tamanho total do log da API desde que o container subiu:"
  docker compose logs --no-log-prefix api | wc -lc | awk '{print "  linhas: " $1 "   bytes: " $2}'
  echo
  echo "Maior linha de log (bytes) e os primeiros 300 caracteres dela:"
  docker compose logs --no-log-prefix api | awk '{ if (length($0) > m) { m = length($0); l = $0 } } END { print "  " m " bytes"; print "  " substr(l, 1, 300) "..." }'
} > "$SAIDA/07-log-da-api.txt"
echo "salvo $SAIDA/07-log-da-api.txt"

echo "Pronto."
