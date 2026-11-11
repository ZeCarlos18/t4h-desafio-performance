# Pesquisa (etapa 03)

Para cada problema do [diagnóstico](diagnostico/README.md): o que a documentação oficial, os artigos e os casos de empresas dizem, as alternativas, o custo de cada uma e o que será testado.

**Como as fontes foram verificadas.** Cada link abaixo foi aberto em 11/11/2026, e o trecho que sustenta a afirmação foi lido na própria página. Os artigos acadêmicos foram conferidos pelo DOI na [Crossref](https://www.crossref.org/), e os dois de ICSE foram lidos nas versões abertas publicadas pelos autores. Nas tabelas, a coluna **"Fonte diz"** é fato com referência. As colunas **"Ganho esperado"** e **"Decisão"** são opinião minha, a ser confirmada ou derrubada pelas medições.

## Fontes

### Documentação oficial

| Id | Fonte | O que sustenta |
|---|---|---|
| O1 | [PostgreSQL 16, 5.4.5 Foreign Keys](https://www.postgresql.org/docs/16/ddl-constraints.html#DDL-CONSTRAINTS-FK) | Declarar uma chave estrangeira não cria índice na coluna que referencia, e muitas vezes vale criar |
| O2 | [PostgreSQL 16, 52.2 How Connections Are Established](https://www.postgresql.org/docs/16/connect-estab.html) | Modelo "um processo por usuário": cada conexão faz o servidor iniciar um processo novo |
| O3 | [PostgreSQL 16, 11.3 Multicolumn Indexes](https://www.postgresql.org/docs/16/indexes-multicolumn.html) | Um índice de várias colunas é mais eficiente quando há igualdade nas colunas da esquerda |
| O4 | [PostgreSQL 16, 11.4 Indexes and ORDER BY](https://www.postgresql.org/docs/16/indexes-ordering.html) | Um índice B-tree pode entregar as linhas já ordenadas, sem uma etapa de ordenação |
| O5 | [PostgreSQL 16, 11.7 Indexes on Expressions](https://www.postgresql.org/docs/16/indexes-expressional.html) | `WHERE lower(col) = ...` usa um índice criado sobre `lower(col)`. Custa mais para manter nas escritas |
| O6 | [PostgreSQL 16, 7.6 LIMIT and OFFSET](https://www.postgresql.org/docs/16/queries-limit.html) | As linhas puladas pelo OFFSET são calculadas mesmo assim, então um OFFSET grande pode ser ineficiente |
| O7 | [PostgreSQL 16, 41.3 Materialized Views](https://www.postgresql.org/docs/16/rules-materializedviews.html) e [REFRESH MATERIALIZED VIEW](https://www.postgresql.org/docs/16/sql-refreshmaterializedview.html) | Uma *view* materializada guarda o resultado em forma de tabela. Ler dela costuma ser bem mais rápido, mas o dado nem sempre está atualizado. `CONCURRENTLY` exige um índice único |
| O8 | [PostgreSQL 16, 20.4 Resource Consumption](https://www.postgresql.org/docs/16/runtime-config-resource.html) | `shared_buffers`: ponto de partida de 25% da memória do servidor. `work_mem`: memória de cada ordenação antes de ir para o disco (padrão 4 MB), que pode ser usada várias vezes ao mesmo tempo |
| O9 | [PostgreSQL 16, 20.7 Query Planning](https://www.postgresql.org/docs/16/runtime-config-query.html) | `effective_cache_size` é uma suposição do planejador: maior favorece índices, menor favorece leitura sequencial |
| O10 | [PostgreSQL 16, 15.1 How Parallel Query Works](https://www.postgresql.org/docs/16/how-parallel-query-works.html) | A consulta paralela inicia processos auxiliares, limitados por `max_parallel_workers_per_gather`. O líder também precisa ler tudo o que os auxiliares produzem |
| O11 | [PostgreSQL 16, F.35 pg_trgm](https://www.postgresql.org/docs/16/pgtrgm.html) | Índices GIN/GiST de trigramas aceleram `LIKE` e `ILIKE` |
| O12 | [node-postgres, Pooling](https://node-postgres.com/features/pooling) | Conectar um cliente novo exige um *handshake* (20 a 30 ms segundo o autor), e o servidor aguenta um número limitado de clientes. O *pool* reaproveita conexões |
| O13 | [node-postgres, Pool API](https://node-postgres.com/apis/pool) | Opções do `pg.Pool`: `max`, `idleTimeoutMillis` |
| O14 | [Express, Performance best practices](https://expressjs.com/en/advanced/best-practice-performance.html) | `console.log` é síncrono para terminal ou arquivo, e não é indicado em produção a não ser que a saída vá para outro programa. Compressão gzip |
| O15 | [Node.js 20, process: A note on process I/O](https://nodejs.org/docs/latest-v20.x/api/process.html) | No Linux, `stdout` em *pipe* é **assíncrono**. Em arquivo ou terminal, é síncrono |
| O16 | [PgBouncer, Configuration](https://www.pgbouncer.org/config.html) | `pool_mode`: *session* (padrão), *transaction* e *statement*, que define quando uma conexão do servidor volta para o pool |

### Acadêmicas ou técnicas primárias

| Id | Fonte | O que sustenta |
|---|---|---|
| A1 | Bayer, R.; McCreight, E. M. Organization and maintenance of large ordered indexes. *Acta Informatica*, 1972. [doi:10.1007/BF00288683](https://doi.org/10.1007/BF00288683) | O artigo que propôs a B-tree, a estrutura do índice padrão do PostgreSQL |
| A2 | Chen, T.-H. et al. Detecting performance anti-patterns for applications developed using object-relational mapping. *ICSE*, 2014. [doi:10.1145/2568225.2568259](https://doi.org/10.1145/2568225.2568259) ([PDF dos autores](https://ece.uwaterloo.ca/~wshang/pubs/peter_icse2014.pdf)) | Define os anti-padrões **"One-by-one processing"** (uma consulta por item, o N+1) e **"Excessive data"** (buscar dados que não são usados). Os autores relatam até 98% de melhora no tempo de resposta ao corrigi-los |
| A3 | Yang, J. et al. How *not* to structure your database-backed web applications: a study of performance bugs in the wild. *ICSE*, 2018. [doi:10.1145/3180155.3180194](https://doi.org/10.1145/3180155.3180194) ([PDF dos autores](https://hyperloop-rails.github.io/220-HowNotStructure.pdf)) | Estudo de 12 aplicações reais e mais de 200 problemas, resumidos em 9 anti-padrões. **Falta de índice** é o problema mais reportado nos *bug trackers*. Também cobrem N+1, dados buscados sem uso e campos que poderiam ser guardados em vez de recalculados. Corrigindo 64 problemas, a aceleração mediana foi de 2× (máximo de 39×), a maioria com menos de 5 linhas alteradas |
| A4 | Nishtala, R. et al. Scaling Memcache at Facebook. *NSDI*, 2013. [USENIX](https://www.usenix.org/conference/nsdi13/technical-sessions/presentation/nishtala) | O Facebook usa um cache em memória (memcached) na frente do banco e atende bilhões de requisições por segundo. É a referência para cache como serviço separado |

### Casos de mercado e literatura técnica

| Id | Fonte | O que sustenta |
|---|---|---|
| M1 | GitLab Docs, [Pagination guidelines](https://docs.gitlab.com/development/database/pagination_guidelines/) | O OFFSET não escala em tabelas grandes: no exemplo deles, o banco lê 1 milhão de linhas para devolver 20, em 5,5 s. Um índice com a coluna de desempate (`project_id, id`) faz a consulta ler no máximo 20 linhas. A paginação por *keyset* é a solução de longo prazo, mas não oferece número de página |
| M2 | Peterse, Y. [Scaling the GitLab database](https://about.gitlab.com/blog/2017/10/02/scaling-the-gitlab-database/). GitLab, 2017 | No PostgreSQL, cada conexão é um processo do sistema operacional. O GitLab usa PgBouncer para que muitos clientes compartilhem poucas conexões (por exemplo, 100 clientes em ~10 conexões) |
| M3 | Martin, D. [Pagination with Relative Cursors](https://shopify.engineering/pagination-relative-cursors). Shopify Engineering | OFFSETs grandes deixavam consultas lentas, ocupavam todas as conexões e faziam consultas rápidas sem relação com elas expirarem na fila. Internamente, a Shopify já usava cursores relativos. Na API externa, só tirou os números de página depois de criar o versionamento da API, porque essa mudança quebra os clientes |
| M4 | Winand, M. [We need tool support for keyset pagination](https://use-the-index-luke.com/no-offset). *Use The Index, Luke* | O *seek method*, ou *keyset pagination*, é mais rápido que o OFFSET e evita resultados que "escorregam" entre as páginas |

## Alternativas por problema

**Restrição que vale para tudo** (PDF, seção 07): o que cada rota devolve não pode mudar, nem status, campos, valores e ordem, nem os parâmetros que ela aceita. Toda alternativa que muda a interface da API foi descartada, mesmo que seja melhor no papel.

### P1. Falta de índices

| Alternativa | Fonte diz | Custo | Ganho esperado (opinião) | Risco | Esforço | Decisão |
|---|---|---|---|---|---|---|
| **Índices B-tree nas chaves estrangeiras** (`itens_pedido.pedido_id`, `pedidos.cliente_id`) | O1, A1, A3 | Espaço em disco (a medir) e escrita um pouco mais lenta. A aplicação só lê | Alto: as consultas de itens e pedidos deixam de ler a tabela inteira | Baixo | Um `.sql` novo | **Testar** |
| **Índice de expressão `lower(email)`** | O5 | Disco e custo de manter nas escritas (O5) | Alto para `cliente-por-email` (41 ms com leitura completa) | Baixo | Um `.sql` | **Testar** |
| Índices "cobrindo" (`INCLUDE`) para leitura só do índice | O4 | Mais disco | Pequeno a mais sobre o índice simples | Baixo | Baixo | Futuro |

### P2. N+1 na rota de pedidos do cliente

| Alternativa | Fonte diz | Custo | Ganho esperado (opinião) | Risco | Esforço | Decisão |
|---|---|---|---|---|---|---|
| **Buscar todos os itens de todos os pedidos de uma vez** (`pedido_id = ANY($1)` com JOIN em produtos), de 32 para 3 consultas | A2 (*one-by-one processing*), A3 | Nenhum recurso a mais | Alto: menos idas ao banco | Médio: a ordem dos itens e o total precisam continuar idênticos, e o contrato verifica isso | Algumas linhas | **Testar** |
| Uma consulta só, montando o JSON no banco (`json_agg`) | A3 | Nenhum | Um pouco maior que a anterior | Alto: datas e números saem formatados pelo banco, com risco de quebrar o contrato | Médio | Descartar (risco ao contrato) |
| Cache da resposta por cliente | A4 | Memória | Esconde o problema sem resolver a causa | Médio | Médio | Descartar |

### P3. Uma conexão nova por consulta

| Alternativa | Fonte diz | Custo | Ganho esperado (opinião) | Risco | Esforço | Decisão |
|---|---|---|---|---|---|---|
| **`pg.Pool` dentro da API** | O2, O12, O13 | Nenhum container a mais. Algumas conexões ficam abertas no banco | Alto em todas as rotas: o diagnóstico mediu 2,7 ms por conexão e 35× menos vazão abrindo uma por consulta | Baixo. O tamanho do pool precisa ser escolhido (padrão `max` = 10) | Algumas linhas | **Testar** |
| PgBouncer como serviço separado | O16, M2 | **Um container a mais (custo)** | Parecido com o pool para 1 instância da API. Brilha com muitas instâncias | Médio: o modo *transaction* muda o comportamento da sessão (O16) | Médio | Futuro: só compensa com várias réplicas da API |

### P4. Paginação de pedidos por status

| Alternativa | Fonte diz | Custo | Ganho esperado (opinião) | Risco | Esforço | Decisão |
|---|---|---|---|---|---|---|
| **Índice `(status, criado_em DESC, id DESC)`**, mantendo o OFFSET | O3, O4, M1 | Disco | Alto: o banco percorre o índice em ordem em vez de ordenar ~300 mil linhas em disco, mas ainda passa pelas linhas do OFFSET (O6) | Baixo | Um `.sql` | **Testar** |
| Buscar só as colunas usadas, sem `observacoes` | A2 (*excessive data*), A3 | Nenhum | Médio: linhas menores para ordenar e transferir | Baixo | Uma linha | **Testar**, junto com o índice ou separado |
| Paginação *keyset* (cursor) | O6, M1, M3, M4 | Nenhum | Muito alto: tempo estável em qualquer página | **Quebra o contrato**: a rota recebe `pagina`, e o *keyset* não oferece número de página (M1). A Shopify precisou versionar a API para fazer essa troca (M3) | Médio | **Descartar** por causa do contrato |
| Contagem por status pré-calculada (*view* materializada) | O7 | Disco mínimo. Precisa de atualização | Alto para a contagem, que hoje lê a tabela inteira | Médio: dado desatualizado se a loja gravasse pedidos | Baixo | Testar depois do índice, se a contagem continuar pesada |

### P5. Relatório de vendas por dia

| Alternativa | Fonte diz | Custo | Ganho esperado (opinião) | Risco | Esforço | Decisão |
|---|---|---|---|---|---|---|
| **Filtro por intervalo** (`criado_em >= inicio AND criado_em < fim + 1 dia`) **+ índice em `criado_em`**, sem buscar `observacoes` | O4, O5, A2 | Disco | Alto: ler só o período pedido | Baixo: para `timestamp` sem fuso, os dois filtros selecionam as mesmas linhas, e o contrato confirma | Baixo | **Testar** |
| Índice de expressão sobre `(criado_em::date)`, mantendo a consulta | O5 | Disco | Parecido | Baixo | Muito baixo | Alternativa, caso a anterior quebre o contrato |
| Somar por dia no banco (`GROUP BY`) em vez de no JavaScript | A3 | Nenhum | Médio: trafegam ~7 linhas em vez de ~13 mil | Médio: os tipos dos números precisam continuar iguais | Médio | Testar depois do filtro |
| Resumo diário pré-calculado (*view* materializada) | O7 | Disco mínimo e atualização | Muito alto | Médio (dado desatualizado) | Médio | Futuro |

### P6. Relatório de produtos mais vendidos

| Alternativa | Fonte diz | Custo | Ganho esperado (opinião) | Risco | Esforço | Decisão |
|---|---|---|---|---|---|---|
| **View materializada com a receita por produto** (20 mil linhas) e um índice | O7, A3 (campos guardados em vez de recalculados) | Disco pequeno. Precisa de `REFRESH` quando os dados mudarem | Muito alto: de ~1,5 s para ler 10 linhas | Médio: o dado fica desatualizado entre um *refresh* e outro. Nesta aplicação nada é gravado | Baixo | **Testar** |
| Cache em memória na API, com validade (TTL) | A4 | Memória da API | Muito alto depois da primeira chamada | Médio: a primeira chamada continua lenta, e cada instância tem o próprio cache | Baixo | Alternativa |
| Redis ou memcached como serviço | A4 | **Um container a mais (custo)** | Igual ao cache em memória para 1 instância | Médio | Médio | Futuro: só faz sentido com várias réplicas da API |

### P7. Parâmetros do PostgreSQL

| Alternativa | Fonte diz | Custo | Ganho esperado (opinião) | Risco | Esforço | Decisão |
|---|---|---|---|---|---|---|
| **`max_parallel_workers_per_gather = 0`** (o container tem 1 CPU) | O10 | Nenhum | Incerto: pode reduzir a disputa pela CPU ou piorar as consultas grandes | Baixo | Uma linha no compose | **Testar** depois de P1 a P6 |
| `effective_cache_size` compatível com os 512 MB do container | O9 | Nenhum | Pequeno: só muda as estimativas do planejador | Baixo | Uma linha | Testar junto com a anterior, se fizer sentido |
| Aumentar `work_mem` | O8 | Memória por operação, multiplicada pelas conexões simultâneas | Pode sumir depois do índice da P4, que elimina a ordenação em disco | Médio: estourar os 512 MB | Uma linha | Só se ainda houver ordenação em disco |
| Aumentar `shared_buffers` | O8 | Memória | A própria documentação sugere 25% da memória como ponto de partida, e o valor atual (128 MB) **já é 25% de 512 MB** | Médio | Uma linha | Descartar por ora (O8) |

### P8. Log com o corpo inteiro da resposta

| Alternativa | Fonte diz | Custo | Ganho esperado (opinião) | Risco | Esforço | Decisão |
|---|---|---|---|---|---|---|
| **Registrar só método, URL, status e duração** | O14, O15 | Nenhum. Reduz disco de log | Pequeno no tempo (a API usa ~7% de CPU). Ganho de custo em armazenamento | Baixo: o log não faz parte do contrato | Uma linha | **Testar** (custo) |
| Logger assíncrono (ex.: pino) | O14 | Dependência nova | Pequeno: no Docker, o `stdout` já é um *pipe* assíncrono no Linux (O15) | Baixo | Médio | Descartar (O15) |

### Custo: reduzir os limites dos containers

A pergunta do desafio também pede que a aplicação fique **mais barata**. Na linha de base, a API usa ~7% de CPU e ~30 MiB dos seus 256 MiB. Depois das otimizações, a ideia é medir com limites menores (por exemplo, API com 0,25 CPU e 128 MB) e verificar se o desempenho se mantém. **Testar** por último.

## Plano de experimentos

Uma mudança por commit, seguindo o ciclo da seção 06 do PDF. A ordem prioriza o impacto medido no diagnóstico: `pedidos-do-cliente` responde por 64,5% do tempo total.

| # | Mudança | Hipótese | Antes |
|---|---|---|---|
| 01 | Índices nas chaves estrangeiras | Deve reduzir o p95 geral, principalmente o de `pedidos-do-cliente`, porque as consultas de itens e pedidos deixam de ler a tabela inteira | Linha de base |
| 02 | Fim do N+1 em `pedidos-do-cliente` | Deve reduzir o p95 dessa rota, porque passam a ser 3 consultas em vez de 2 + pedidos + itens | 01 |
| 03 | `pg.Pool` na API | Deve aumentar as requisições/s em todas as rotas, porque cada consulta deixa de pagar uma conexão e um processo novos | 02 |
| 04 | Índice `lower(email)` | Deve reduzir o p95 de `cliente-por-email`, porque a busca deixa de ler os 100 mil clientes | 03 |
| 05 | Índice `(status, criado_em, id)` e só as colunas usadas | Deve reduzir o p95 de `pedidos-por-status`, porque elimina a ordenação em disco | 04 |
| 06 | Vendas por dia com filtro por intervalo e índice | Deve reduzir o p95 de `vendas-por-dia`, porque o banco passa a ler só o período | 05 |
| 07 | View materializada de produtos mais vendidos | Deve reduzir o p95 de `top-produtos` e a CPU do banco, porque o cálculo deixa de ser refeito a cada chamada | 06 |
| 08 | `max_parallel_workers_per_gather = 0` | Pode reduzir a CPU do banco, porque os processos paralelos deixam de disputar 1 CPU (hipótese fraca) | 07 |
| 09 | Log sem o corpo da resposta | Deve reduzir o tamanho do log sem mudar o tempo de resposta | 08 |
| 10 | Limites menores de CPU e memória | Deve manter o desempenho de 09 com menos recursos | 09 |

A ordem pode mudar conforme os resultados: uma mudança resolve um gargalo e revela o próximo (PDF, etapa 03). O que não for testado vai para o `proximos-testes.md`, com a ficha pedida no PDF.
