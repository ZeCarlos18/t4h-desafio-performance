# Índices, menos idas ao banco e um relatório pré-calculado deram 16× mais vazão à API da loja, sem recurso a mais

Autor: Jose Carlos. Desafio da 2ª fase do Estágio em Pesquisa e Inovação 2026 da Tech for Humans.

## 1. Resumo

Sob carga, a API da loja (Node.js 20 + PostgreSQL 16) atendia 2,96 requisições/s, e 5% delas levavam mais de 22,5 s. O banco estava saturado por quatro causas:
- falta de índices;
- uma rota com 32 consultas por chamada;
- uma conexão nova por consulta;
- um relatório recalculado a cada chamada.

Oito mudanças, cada uma medida três vezes, levaram a 46,95 requisições/s (~16×) e p95 de 947 ms (−95,8%), sem mais recursos e sem mudar respostas. O gargalo passou para a API.

## 2. Contexto e diagnóstico

A aplicação roda em Docker Compose: banco com 1 CPU e 512 MB, API com 0,5 CPU e 256 MB. O `scripts/medir.sh` usa 20 usuários virtuais por 60 s e confere se as 42 respostas de referência continuam iguais. O p95 é o tempo abaixo do qual ficam 95% das requisições.

Na linha de base (mediana de 3 execuções, [arquivo](../analise/saidas/01-indices-fk-medianas.md)), o banco usava 94,3% da sua CPU e a API, 7,2%. A API passava o tempo esperando o banco. O [diagnóstico](../diagnostico/README.md) salvou planos de consulta (`EXPLAIN ANALYZE`) e contagens:

- **Rota `GET /clientes/:id/pedidos`:**
    - recebe 21,8% das requisições e responde por 64,5% do tempo total ([tempo por rota](../diagnostico/saidas/08-tempo-por-rota-linha-de-base.txt));
    - faz 32 consultas por chamada ([conexões](../diagnostico/saidas/05-conexoes-por-requisicao.txt));
    - lê 1,5 milhão de itens para achar os de um pedido, em 83 ms ([plano](../diagnostico/saidas/04c2-explain-pedidos-do-cliente-itens.txt)).
- **Conexões:** conectar a cada consulta derrubou o pgbench de ~8.100 para ~233 consultas/s ([pgbench](../diagnostico/saidas/06-custo-de-conexao-pgbench.txt)).
- **Página de pedidos por status:** ordena ~300 mil linhas em disco, em 319 ms ([plano](../diagnostico/saidas/04d2-explain-pedidos-por-status-pagina.txt)).
- **Relatórios:** "vendas por dia" leva 361 ms ([plano](../diagnostico/saidas/04f-explain-vendas-por-dia.txt)) e "produtos mais vendidos", 1.506 ms ([plano](../diagnostico/saidas/04g-explain-top-produtos.txt)).

Hipótese de causa:
- **Índices:** sem índice nas colunas de busca, cada consulta lê a tabela inteira e satura a única CPU do banco.
- **N+1:** o número de consultas da rota de pedidos cresce com o histórico do cliente.
- **Conexões:** cada consulta paga uma conexão e um processo novos no banco.
- **Relatório:** os produtos mais vendidos são recalculados do zero, embora os dados não mudem.

## 3. Estado da arte

### Índices
A B-tree, proposta por Bayer e McCreight [1], é a estrutura do índice padrão do PostgreSQL. A documentação lembra três pontos:
- uma chave estrangeira não ganha índice automático [2];
- um índice de várias colunas pode entregar as linhas já ordenadas [3];
- uma busca por `lower(email)` precisa de um índice sobre essa mesma expressão [4].

No estudo de Yang et al. com 12 aplicações reais, a falta de índice é o problema de desempenho mais reportado. A aceleração mediana das correções foi de 2×, a maioria com menos de 5 linhas alteradas [5].

### Menos idas ao banco e menos dados
Chen et al. chamam de *one-by-one processing* o padrão de uma consulta por item, conhecido como N+1, e de *excessive data* a busca de colunas que não são usadas. Os autores relatam até 98% de melhora ao corrigi-los [6]. Yang et al. encontram os mesmos padrões [5].

### Reaproveitar conexões
No PostgreSQL, cada conexão inicia um processo novo no servidor [7]. A documentação do node-postgres recomenda um *pool*, com 10 conexões por padrão, que mantém as conexões abertas e as reaproveita [8]. Quando há muitas instâncias da aplicação, o GitLab usa PgBouncer para que muitos clientes dividam poucas conexões [9].

### Pré-calcular ou guardar em cache
Uma *view* materializada guarda o resultado de uma consulta como tabela. Ler dela é rápido, mas o dado só muda com `REFRESH` [10]. Num serviço separado, o Facebook usa memcached na frente do banco em escala de bilhões de requisições por segundo [11].

### Paginação
As linhas puladas pelo `OFFSET` continuam sendo lidas [12]. GitLab [13], Shopify [14] e Winand [15] recomendam a paginação por cursor (*keyset*). Ela não tem número de página, e a Shopify só a adotou na API pública depois de versionar a API [14].

## 4. Alternativas consideradas

| Alternativa | Custo | Desempenho | Risco | Esforço |
| --- | --- | --- | --- | --- |
| A. Índices e consultas corrigidas (N+1), dentro do que já existe | Disco: +58 MB no total | Medido: maior parte do ganho (seção 6) | Baixo; o contrato confere cada resposta | Baixo: `.sql` novos e poucas linhas |
| B. `pg.Pool` na API | Nenhum recurso a mais | Medido: +16,7% de vazão | Fila no pool (hipótese, seção 6) | Algumas linhas |
| C. *View* materializada para o relatório | 2,3 MB e `REFRESH` de 1,33 s | Medido: +151% de vazão | Dado desatualizado se a loja gravar | Um `.sql` e uma consulta |
| D. PgBouncer ou Redis como serviço | Um container a mais cada | Esperado: perto de zero com 1 instância da API | Médio: modo de sessão, invalidação | Médio |
| E. Paginação *keyset* | Nenhum | Esperado: tempo estável em qualquer página | Quebra o contrato (a rota recebe `pagina`) | Médio |
| F. Mais CPU e memória para o banco | Mais custo de máquina | Não medido | Esconde a causa | Mínimo |

A, B e C atacam as causas que o diagnóstico mediu, e as colunas de desempenho delas trazem números medidos. As de D, E e F são expectativas tiradas das fontes, não medições. D é a solução de mercado para um problema que esta aplicação ainda não tem, que é ter muitas réplicas da API [9], [11]. E é tecnicamente melhor que o `OFFSET` [13], [15], mas muda a interface da API, o que o desafio proíbe. F vai contra a metade "mais barata" da pergunta. **Opinião, não medida:** com consultas que leem tabelas inteiras, mais CPU só dividiria o mesmo desperdício por mais núcleos.

## 5. Solução escolhida e por quê

Escolhi A, B e C, aplicadas uma por vez.

O argumento é de evidência e de custo:
- o banco estava saturado por leituras completas e por consultas repetidas, e as três alternativas removem trabalho em vez de comprar capacidade;
- nenhuma adiciona container nem aumenta limites;
- a literatura indica que esse tipo de correção é pequeno e rende muito [5], [6].

A ordem seguiu o diagnóstico: primeiro a rota com 64,5% do tempo, depois o que o resultado anterior revelou como novo gargalo.

Descartei:
- **D:** o custo de mais um serviço não se paga com uma instância da API;
- **E:** quebra o contrato;
- **F:** aumenta o custo sem tratar a causa;
- **`json_agg`** para montar a resposta no banco: risco de mudar a formatação de datas e números (detalhes no [pesquisa.md](../pesquisa.md)).

## 6. Experimento e resultado

Cada linha compara a mediana de 3 execuções com a da mudança anterior. Cada mudança teve um commit, a conferência do contrato (42 de 42 iguais) e um commit separado com os resultados. Os detalhes estão no [experimentos.md](../experimentos.md).

| Mudança | Hipótese | p95 antes → depois | req/s antes → depois | CPU/memória | Pastas de resultados | Conclusão |
| --- | --- | --- | --- | --- | --- | --- |
| 01 Índices nas chaves estrangeiras | Itens e pedidos deixam de ler a tabela inteira | 22.484 → 10.906 ms | 2,96 → 5,57 | Banco 94,3 → 96,7% | [medianas](../analise/saidas/01-indices-fk-medianas.md), [resumo](../resultados/20261111-202249-01-indices-fk/resumo.txt) | Confirmada. Consultas de 83 ms para 0,68 ms |
| 02 Fim do N+1 | 3 consultas em vez de 32 | 10.906 → 13.370 ms | 5,57 → 7,05 | Banco 96,7 → 90,8% | [medianas](../analise/saidas/02-fim-n-mais-1-medianas.md), [resumo](../resultados/20261115-092129-02-fim-n-mais-1/resumo.txt) | Rota −81%. p95 geral subiu (abaixo) |
| 03 `pg.Pool` | Sem conexão nova por consulta | 13.370 → 7.431 ms | 7,05 → 8,23 | Banco 90,8 → 91,6% | [medianas](../analise/saidas/03-pool-conexoes-medianas.md), [resumo](../resultados/20261115-102839-03-pool-conexoes/resumo.txt) | Em parte: mediana +58% |
| 04 Índice `lower(email)` | Busca sem ler 100 mil clientes | 7.431 → 7.470 ms | 8,23 → 8,70 | Banco 91,6 → 88,8% | [medianas](../analise/saidas/04-indice-email-medianas.md), [resumo](../resultados/20261115-104344-04-indice-email/resumo.txt) | Rota −23,8%. Geral incerto |
| 05 Índice `(status, criado_em, id)` | Fim da ordenação em disco | 7.470 → 3.596 ms | 8,70 → 15,68 | Banco 88,8 → 97,6% | [medianas](../analise/saidas/05-indice-status-medianas.md), [resumo](../resultados/20261115-111310-05-indice-status/resumo.txt) | Confirmada. Todas as rotas melhoraram |
| 06 Índice `(criado_em::date)` | Relatório lê só o período | 3.596 → 3.906 ms | 15,68 → 17,80 | Banco 97,6 → 96,8% | [medianas](../analise/saidas/06-indice-data-medianas.md), [resumo](../resultados/20261115-112422-06-indice-data/resumo.txt) | Consulta 361 → 15 ms, rota só −7,3%. Incerto |
| 07 *View* para `top-produtos` | Cálculo deixa de ser refeito | 3.906 → 993 ms | 17,80 → 44,70 | Banco 96,8 → 63,5%; API 18,6 → 42,6% | [medianas](../analise/saidas/07-view-top-produtos-medianas.md), [resumo](../resultados/20261115-114433-07-view-top-produtos/resumo.txt) | Confirmada. Gargalo foi para a API |
| 09 Log sem o corpo | Log menor, mesmo tempo | 993 → 947 ms | 44,70 → 46,95 | API 42,6 → 43,0% | [medianas](../analise/saidas/09-log-sem-corpo-medianas.md), [resumo](../resultados/20261115-120331-09-log-sem-corpo/resumo.txt) | Log −93% por requisição. Tempo igual |

![Dois gráficos de barras: requisições por segundo sobem de 2,96 na linha de base para 46,95 no experimento 09, e o p95 geral cai de 22.484 ms para 947 ms, com os saltos maiores nos experimentos 01, 05 e 07](img/evolucao.svg)

**O que não funcionou como esperado:**
- **No 02, o p95 geral subiu 22,6%.** O `medir.sh` usa o modelo fechado do k6, em que cada usuário só faz a próxima requisição quando a anterior termina [16]. O tempo economizado virou mais chamadas às rotas pesadas.
- **No 03, a mediana piorou 58%.** Hipótese não verificada: as rotas leves esperam na fila do *pool* atrás das pesadas.
- **No 04 e no 06, o ganho geral ficou dentro da variação entre execuções.**
- **No 09, a hipótese revisada falhou.** Eu esperava que tirar o corpo do log liberasse CPU da API, mas a CPU ficou igual. A documentação já indicava que o `stdout` em *pipe* não bloqueia no Linux [17].
- **O experimento 08** (desligar a consulta paralela) foi adiado, porque o banco deixou de ser o gargalo.

## 7. Limites e testes futuros

- **Uma máquina, um perfil de carga.** Tudo foi medido com 20 usuários em modelo fechado. Com carga a taxa fixa (modelo aberto [16]), o p95 pode mudar. Não verifiquei.
- **Ruído.** A variação entre execuções pode passar de 30%; os ganhos de 04, 06 e 09 cabem nela.
- **Mais barato, só em parte.** Nenhum limite foi reduzido, e o banco cresceu 58 MB. O ganho de custo medido é o log: ~5,0 GB por dia antes e ~0,34 GB depois, supondo essa carga o dia todo. Reduzir a CPU do banco, que usa 64,6%, é o primeiro teste pendente.
- **A *view* fica parada no tempo.** Com pedidos novos, o relatório atrasa até o `REFRESH`.
- **O `OFFSET` ainda cresce com a página:** 10,8 ms na página 500 e 20,0 ms na 1000 ([evidências](../analise/saidas/05-indice-status-evidencias.txt)).
- **A API está no limite de CPU**, por motivo ainda não medido (falta *profiling*).
- **O `awk` do `medir.sh` erra os máximos** do `recursos.txt`. Recalculei-os do `recursos.csv`.

**O que derrubaria a conclusão:** remedir a linha de base e o estado final em outra máquina sem ver diferença de ordem de grandeza, ou achar uma resposta diferente fora dos 42 casos do contrato. Os próximos testes estão em [proximos-testes.md](../proximos-testes.md).

## 8. Referências

1. Bayer, R.; McCreight, E. M. Organization and maintenance of large ordered indexes. *Acta Informatica*, 1972. https://doi.org/10.1007/BF00288683. Acesso em 11/11/2026.
2. PostgreSQL Global Development Group. PostgreSQL 16, 5.4.5 Foreign Keys. https://www.postgresql.org/docs/16/ddl-constraints.html#DDL-CONSTRAINTS-FK. Acesso em 11/11/2026.
3. PostgreSQL Global Development Group. PostgreSQL 16, 11.3 Multicolumn Indexes e 11.4 Indexes and ORDER BY. https://www.postgresql.org/docs/16/indexes-multicolumn.html e https://www.postgresql.org/docs/16/indexes-ordering.html. Acesso em 11/11/2026.
4. PostgreSQL Global Development Group. PostgreSQL 16, 11.7 Indexes on Expressions. https://www.postgresql.org/docs/16/indexes-expressional.html. Acesso em 11/11/2026.
5. Yang, J. et al. How *not* to structure your database-backed web applications: a study of performance bugs in the wild. *ICSE*, 2018. https://doi.org/10.1145/3180155.3180194. Acesso em 11/11/2026.
6. Chen, T.-H. et al. Detecting performance anti-patterns for applications developed using object-relational mapping. *ICSE*, 2014. https://doi.org/10.1145/2568225.2568259. Acesso em 11/11/2026.
7. PostgreSQL Global Development Group. PostgreSQL 16, 52.2 How Connections Are Established. https://www.postgresql.org/docs/16/connect-estab.html. Acesso em 11/11/2026.
8. node-postgres. Pooling e Pool API. https://node-postgres.com/features/pooling e https://node-postgres.com/apis/pool. Acesso em 11/11/2026 (Pool API conferida de novo em 18/11/2026).
9. Peterse, Y. Scaling the GitLab database. GitLab, 2017. https://about.gitlab.com/blog/2017/10/02/scaling-the-gitlab-database/. Acesso em 11/11/2026.
10. PostgreSQL Global Development Group. PostgreSQL 16, 41.3 Materialized Views e REFRESH MATERIALIZED VIEW. https://www.postgresql.org/docs/16/rules-materializedviews.html e https://www.postgresql.org/docs/16/sql-refreshmaterializedview.html. Acesso em 11/11/2026.
11. Nishtala, R. et al. Scaling Memcache at Facebook. *NSDI*, 2013. https://www.usenix.org/conference/nsdi13/technical-sessions/presentation/nishtala. Acesso em 11/11/2026.
12. PostgreSQL Global Development Group. PostgreSQL 16, 7.6 LIMIT and OFFSET. https://www.postgresql.org/docs/16/queries-limit.html. Acesso em 11/11/2026.
13. GitLab. Pagination guidelines. https://docs.gitlab.com/development/database/pagination_guidelines/. Acesso em 11/11/2026.
14. Martin, D. Pagination with Relative Cursors. Shopify Engineering. https://shopify.engineering/pagination-relative-cursors. Acesso em 11/11/2026.
15. Winand, M. We need tool support for keyset pagination. *Use The Index, Luke*. https://use-the-index-luke.com/no-offset. Acesso em 11/11/2026.
16. Grafana Labs. k6, Open and closed models. https://grafana.com/docs/k6/latest/using-k6/scenarios/concepts/open-vs-closed/. Acesso em 11/11/2026.
17. OpenJS Foundation. Node.js 20, process: A note on process I/O. https://nodejs.org/docs/latest-v20.x/api/process.html. Acesso em 11/11/2026.

## 9. Uso de IA

Usei o Claude (Anthropic) como assistente no diagnóstico, na busca de fontes, na escrita do código, nos scripts de análise e na redação dos textos. Verifiquei abrindo cada fonte citada e lendo o trecho que sustenta a afirmação, e conferindo cada número nos arquivos gerados pelo `scripts/medir.sh` e pelos scripts de `analise/`. Nenhum resultado foi digitado à mão.
