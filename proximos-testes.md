# Próximos testes

Ideias pesquisadas que **não foram aplicadas nem medidas**. Todas têm o status **"Pesquisada, teste futuro"**. Nenhuma ficha traz resultado: o "ganho esperado" é **hipótese**, a ser confirmada ou derrubada com o mesmo ciclo dos [experimentos](experimentos.md): commit da mudança, `scripts/verificar-contrato.sh comparar`, 3 execuções de `scripts/medir.sh` com o mesmo rótulo e comparação das medianas com `analise/medianas.js`.

**Ponto de partida de todas as fichas:** o experimento 09 (`09-log-sem-corpo`), com 46,95 req/s, p95 de 947 ms, API com 43,0% de CPU média (limite de 50%) e banco com 64,6% de 1 CPU e 465 MiB de memória média, de 512 MiB ([medianas](analise/saidas/09-log-sem-corpo-medianas.md)).

**Fontes.** Os ids (O1, A2, M1...) são os do [pesquisa.md](pesquisa.md), abertos em 11/11/2026. As fontes marcadas como **novas** foram conferidas em 18/11/2026 no texto-fonte oficial da documentação, que é o mesmo das páginas: a documentação do PostgreSQL na branch `REL_16_STABLE` do repositório [postgres/postgres](https://github.com/postgres/postgres/tree/REL_16_STABLE/doc/src/sgml), a do node-postgres em [brianc/node-postgres](https://github.com/brianc/node-postgres/tree/master/docs/pages) e a do Docker em [docker/docs](https://github.com/docker/docs/tree/main/content). A página de linha de comando do Node.js foi aberta diretamente.

## Ordem sugerida

| # | Ideia | Por que nesta posição |
| --- | --- | --- |
| 1 | Profiling da CPU da API | A API é o gargalo atual, e sem medir não dá para escolher a próxima mudança nela |
| 2 | Reduzir o limite de CPU do banco (experimento 10) | É a metade "mais barata" da pergunta do desafio, e o banco tem folga |
| 3 | Tamanho do pool e fila de espera | Testa a hipótese que ficou aberta no experimento 03 |
| 4 | Buscar só as colunas usadas | Pouco esforço e risco baixo ao contrato |
| 5 | Somar vendas por dia no banco | Ataca o trabalho que sobrou na rota `vendas-por-dia` |
| 6 | Contagem por status pré-calculada | Testa a hipótese do experimento 06 |
| 7 a 13 | As demais | Ganho esperado menor, custo maior ou quebra do contrato |

---

## 1. Profiling da CPU da API

- **Problema:** depois do experimento 07, a API usa em média 43% de um limite de 50% (0,5 CPU), com picos de 52% ([medianas do 09](analise/saidas/09-log-sem-corpo-medianas.md)). O experimento 09 mostrou que o log **não** era o que ocupava a CPU. O que ocupa ainda não foi medido.
- **Fonte:** Node.js 20, opção `--cpu-prof` ([documentação da linha de comando](https://nodejs.org/docs/latest-v20.x/api/cli.html#--cpu-prof), **nova**): "Starts the V8 CPU profiler on start up, and writes the CPU profile to disk".
- **Ganho esperado (hipótese):** nenhum por si só. É um diagnóstico que aponta a próxima mudança. Candidatos não verificados: converter as respostas em JSON, o Express e a leitura das linhas que chegam do `pg`.
- **Como testaria:**
    1. Subir a API com `node --cpu-prof --cpu-prof-dir=/tmp/perfil src/server.js`, por um `command` só para esse teste, num commit à parte que depois seria desfeito.
    2. Rodar uma carga com os mesmos parâmetros do `medir.sh` e encerrar o processo para gravar o `.cpuprofile`.
    3. Copiar o arquivo para `diagnostico/saidas/` e listar as funções com mais tempo próprio.
    - Essa medição não serve de comparação de desempenho, porque o profiler também consome CPU.
- **O que precisaria:** nada além do que já existe. O arquivo abre no Chrome DevTools.

## 2. Reduzir o limite de CPU do banco (experimento 10, custo)

- **Problema:** a pergunta do desafio pede uma aplicação mais rápida **e mais barata**. No experimento 09, o banco usa 64,6% de média do seu limite de 1 CPU ([medianas do 09](analise/saidas/09-log-sem-corpo-medianas.md)).
- **Fonte:** Docker Compose, `deploy.resources.limits.cpus` ([referência do Compose](https://docs.docker.com/reference/compose-file/deploy/), **nova**): "`cpus` configures a limit or reservation for how much of the available CPU resources, as number of cores, a container can use".
- **Ganho esperado (hipótese):** 25% menos CPU reservada para o banco (de 1,0 para 0,75), com vazão e p95 próximos aos do 09, porque o gargalo atual é a API. Pode falhar: a CPU **máxima** do banco ainda chega a 101% ([mesmo arquivo](analise/saidas/09-log-sem-corpo-medianas.md)), então os picos podem virar fila.
- **Como testaria:** trocar `cpus: "1.0"` por `cpus: "0.75"` no serviço `banco` do `docker-compose.yml`, commitar, aplicar com `docker compose up -d --build` (o compose mudou, não é `.sql`) e medir 3 vezes com o rótulo `10-banco-cpu-075`, contra o `09-log-sem-corpo`. Se a vazão cair muito, o registro é "Aplicada, sem ganho", com a explicação.
- **O que **não** reduzir:**
    - **A CPU da API:** está no teto.
    - **A memória do banco:** média de 465 MiB e máxima de 491 MiB, de 512 MiB.
- **O que precisaria:** a mesma máquina das outras medições (o README avisa que medições de máquinas diferentes não são comparáveis) e cerca de 10 minutos.

## 3. Tamanho do pool e fila de espera

- **Problema:** no experimento 03, o pool de 10 conexões melhorou a vazão e o p95 geral, mas a mediana subiu 58%. As rotas leves pioraram ([experimentos.md, 03](experimentos.md#03-pool-de-conexões-na-api)). Hipótese não verificada: as rotas leves esperam na fila do pool atrás das pesadas.
- **Fonte:** node-postgres, Pool API (O13): o `max` padrão é 10, e `pool.waitingCount` é "the number of queued requests waiting on a client when all clients are checked out. It can be helpful to monitor this number to see if you need to adjust the size of the pool" (texto conferido de novo em 18/11/2026).
- **Ganho esperado (hipótese):** pequeno agora. Depois dos experimentos 05 a 07, as consultas pesadas ficaram rápidas, e a fila deve ter diminuído. É isso que o teste confirmaria ou derrubaria.
- **Como testaria:**
    1. **Primeiro, medir sem mudar:** registrar `pool.waitingCount` e `pool.totalCount` a cada segundo durante uma carga, num commit de diagnóstico. A saída vai para `diagnostico/saidas/`.
    2. **Se houver fila,** um experimento por valor de `max` (por exemplo, 5 e 20), cada um com o seu commit e as suas 3 medições.
    - Mais conexões significam mais processos no banco (O2) e mais memória, e o banco já está perto de 512 MiB.
- **O que precisaria:** algumas linhas na API.

## 4. Buscar só as colunas usadas

- **Problema:** `GET /pedidos` e `GET /relatorios/vendas-por-dia` leem a coluna `observacoes`, que a resposta não usa ([`api/src/rotas.js`](api/src/rotas.js)). No relatório, são 3,4 MB em 12.922 linhas para 7 dias ([diagnóstico 04f](diagnostico/saidas/04f-explain-vendas-por-dia.txt)).
- **Fonte:** Chen et al. (A2), anti-padrão *excessive data*. Yang et al. (A3) também listam dados buscados sem uso.
- **Ganho esperado (hipótese):** menos bytes do banco para a API e menos objetos montados pela API, que hoje é o gargalo de CPU.
- **Como testaria:** trocar `SELECT *` pelas colunas que a resposta usa em `pedidos-por-status`, e tirar `p.observacoes` do relatório. Um commit por rota, com o contrato conferido e 3 medições cada.
- **O que precisaria:** nada. Risco baixo, porque a resposta já é montada campo a campo.

## 5. Somar vendas por dia no banco

- **Problema:** depois do experimento 06, a consulta do relatório leva de 15 a 37 ms, mas o p95 da rota caiu só 7,3% ([experimentos.md, 06](experimentos.md#06-índice-para-o-relatório-de-vendas-por-dia)). As cerca de 13 mil linhas ainda viajam até a API e são somadas em JavaScript.
- **Fonte:** Yang et al. (A3), computação que poderia ser feita no banco.
- **Ganho esperado (hipótese):** de ~13 mil linhas para até 31 por chamada, menos CPU na API.
- **Como testaria:** `GROUP BY` por dia, com `count(DISTINCT p.id)`, `sum(quantidade)` e `sum(quantidade * preco_unitario_centavos)`, e conversão para `Number` na API.
- **Risco ao contrato:** `sum` de `integer` no PostgreSQL devolve `bigint`, que o `pg` entrega como texto. O dia precisa sair no mesmo formato `AAAA-MM-DD`, e a ordem tem que continuar crescente. O verificador de contrato tem 7 casos dessa rota.
- **O que precisaria:** algumas linhas na API.

## 6. Contagem por status pré-calculada

- **Problema:** no experimento 06, o p95 de `pedidos-por-status` subiu 60% de forma consistente, sem mudança de plano ([plano](analise/saidas/06-indice-data-plano-pedidos-por-status.txt)). Hipótese não verificada: a contagem, que percorre cerca de 300 mil entradas do índice por requisição (22,6 ms sem carga), ficou entre as consultas mais caras.
- **Fonte:** PostgreSQL 16, views materializadas (O7).
- **Ganho esperado (hipótese):** contagem de ~20 ms para menos de 1 ms, com menos CPU do banco.
- **Como testaria:** `banco/08-contagem-por-status.sql` com uma view materializada de 4 linhas (`status`, `total`). A rota lê dali e mantém `Number(total)`.
- **Risco:** o mesmo da view do experimento 07. O dado fica parado até o `REFRESH`, o que vale aqui porque a aplicação não grava, mas não valeria numa loja real sem uma estratégia de atualização (ficha 8).
- **O que precisaria:** um `.sql` novo e uma linha na API.

## 7. Desligar a consulta paralela (experimento 08 adiado)

- **Problema:** o banco tem 1 CPU, e o PostgreSQL usa até 2 processos auxiliares por consulta ([diagnóstico 02](diagnostico/saidas/02-configuracao-postgres.txt)).
- **Fonte:** PostgreSQL 16, 20.4 e 15.1 (O8, O10). A documentação de `max_parallel_workers_per_gather` diz: "The default value is 2. Setting this value to 0 disables parallel query execution". Também diz que cada processo auxiliar tem "roughly the same impact on the system as an additional user session" (conferido em 18/11/2026).
- **Ganho esperado (hipótese, fraca):** pequeno. Depois dos índices e da view, quase nenhuma consulta frequente usa plano paralelo, e o banco deixou de ser o gargalo. Foi adiado por isso ([experimentos.md, 09](experimentos.md#09-log-sem-o-corpo-da-resposta)).
- **Como testaria:** `command: ["postgres", "-c", "max_parallel_workers_per_gather=0"]` no serviço `banco`, aplicar com `docker compose up -d --build`, conferir com `SHOW` e medir 3 vezes.
- **O que precisaria:** uma linha no compose. Combina com a ficha 2, mas mudaria duas coisas de uma vez, então fica em commit separado.

## 8. Estratégia de atualização da view `receita_por_produto`

- **Problema:** a view do experimento 07 só muda com `REFRESH`, que levou 1,33 s ([experimentos.md, 07](experimentos.md#07-produtos-mais-vendidos-pré-calculados)). Numa loja que grava pedidos, o relatório ficaria desatualizado.
- **Fonte:** PostgreSQL 16, `REFRESH MATERIALIZED VIEW` (O7): `CONCURRENTLY` atualiza sem bloquear as leituras, mas exige um índice único que cubra todas as linhas.
- **Ganho esperado (hipótese):** não é desempenho, é **correção** num cenário com escrita.
- **Como testaria:**
    1. Criar um índice único em `receita_por_produto(id)`.
    2. Simular escritas e rodar `REFRESH ... CONCURRENTLY` de tempos em tempos durante uma carga.
    3. Medir o efeito do refresh no p95 das outras rotas.
- **O que precisaria:** uma decisão de negócio, isto é, quanto atraso o relatório aceita, e um agendador (um container a mais ou a extensão `pg_cron`).

## 9. `ANALYZE` depois de criar os índices de expressão

- **Problema:** no experimento 04, o planejador estimou 500 linhas para a busca por e-mail, e veio 1 ([evidências](analise/saidas/04-indice-email-evidencias.txt)). O índice foi usado assim mesmo.
- **Fonte:** PostgreSQL 16, `CREATE INDEX`, notas (**nova**, [página](https://www.postgresql.org/docs/16/sql-createindex.html)): "For new expression indexes, it is necessary to run ANALYZE or wait for the autovacuum daemon to analyze the table to generate statistics for these indexes". Isso apoia a hipótese de que o `ANALYZE` do `02-dados.sql` roda antes de os índices de expressão (04 e 06) existirem.
- **Ganho esperado (hipótese):** estimativas melhores para `lower(email)` e `criado_em::date`. Pode não mudar nenhum plano, porque os índices já são escolhidos.
- **Como testaria:** `banco/08-analyze.sql` com `ANALYZE clientes; ANALYZE pedidos;`. Comparar a estimativa nos `EXPLAIN` antes e depois, salvos em arquivo, e só então medir a carga.
- **O que precisaria:** um `.sql` de duas linhas e a recriação do banco.

## 10. Índices cobrindo (`INCLUDE`)

- **Fonte:** PostgreSQL 16, 11.9 Index-Only Scans and Covering Indexes (**nova**, [página](https://www.postgresql.org/docs/16/indexes-index-only-scans.html)). Um índice pode levar colunas "que são só carga", com `INCLUDE`, para a consulta ser respondida sem ler a tabela, desde que o mapa de visibilidade esteja em dia.
- **Ganho esperado (hipótese):** pequeno. Por exemplo, `pedidos(status, criado_em DESC, id DESC) INCLUDE (cliente_id)` evitaria ler a tabela na página de pedidos, mas **só depois** da ficha 4 (sem `SELECT *`).
- **Como testaria:** um `.sql` novo trocando o índice do experimento 05, conferir `Index Only Scan` e `Heap Fetches` no `EXPLAIN ANALYZE` e medir.
- **O que precisaria:** disco a mais (medir com `pg_relation_size`).

## 11. Busca de produtos com `pg_trgm`

- **Problema:** `busca-produtos` usa `ILIKE '%termo%'`, que um B-tree não atende ([diagnóstico 04e](diagnostico/saidas/04e-explain-busca-produtos.txt)). Hoje a rota tem p95 de 727 ms sob carga, no geral do 09.
- **Fonte:** PostgreSQL 16, F.35 pg_trgm (O11): índices GIN e GiST de trigramas aceleram `LIKE` e `ILIKE`.
- **Ganho esperado (hipótese):** moderado na consulta. Com 20 mil produtos, a leitura completa já é barata, então o efeito geral pode ser pequeno.
- **Como testaria:** `CREATE EXTENSION pg_trgm` e um índice GIN em `produtos(nome gin_trgm_ops)`, num `.sql` novo, com `EXPLAIN ANALYZE` antes e depois e 3 medições.
- **Risco ao contrato:** a ordem (`ORDER BY nome, id LIMIT 20`) continua sendo feita pelo banco, então a resposta não muda, mas o contrato confere.

## 12. PgBouncer, Redis ou memcached

- **Fontes:** PgBouncer (O16) e o caso do GitLab (M2). Memcache no Facebook (A4).
- **Ganho esperado (hipótese):** com **uma** instância da API, perto de zero além do `pg.Pool` que já existe. Esses serviços compensam quando há várias réplicas da API disputando conexões ou repetindo leituras.
- **Custo:** **um container a mais cada**, que precisaria entrar na comparação de CPU e memória.
- **Como testaria:** só faz sentido num cenário com 2 ou mais réplicas da API, que mudaria a forma de medir. Ficaria num estudo separado.

## 13. Paginação *keyset*

- **Fontes:** GitLab (M1), Shopify (M3), Winand (M4) e PostgreSQL 7.6 (O6).
- **Ganho esperado (hipótese):** tempo estável em qualquer página, sem percorrer as linhas do `OFFSET`. Hoje a página 1000 leva 20,0 ms, contra 10,8 ms da página 500 ([evidências do 05](analise/saidas/05-indice-status-evidencias.txt)).
- **Por que não agora:** **quebra o contrato**. A rota recebe `pagina`, e o *keyset* não tem número de página (M1). A Shopify só fez essa troca depois de criar o versionamento da API (M3).
- **Como testaria:** numa rota nova (por exemplo, `/v2/pedidos?status=&depois_de=`), mantendo a atual, com uma carga própria.
