# Diagnóstico (etapa 02)

Onde a aplicação perde tempo e recursos, com a evidência de cada conclusão. Nada aqui muda a aplicação: os scripts só leem.

## Como repetir

Com a aplicação no ar (`docker compose up -d --build`), dentro desta pasta:

```bash
diagnostico/coletar.sh
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD":/w -w /w node:20.18.0-alpine \
  node diagnostico/tempo-por-rota.js resultados/*-00-linha-de-base > diagnostico/saidas/08-tempo-por-rota-linha-de-base.txt
```

As saídas ficam em [`saidas/`](saidas/). Cada arquivo traz no cabeçalho a data e o commit que o gerou.

## Visão geral

**O gargalo é o banco, não a API.** Na linha de base, o container do banco usou em média ~97% do seu limite de 1 CPU, e o da API ~7% (o limite dela é 0,5 CPU) ([recursos da execução 3](../resultados/20261109-203226-00-linha-de-base/recursos.txt)). A API passa a maior parte do tempo esperando o banco.

**Uma rota concentra o tempo.** Somando as 3 medições da linha de base ([08](saidas/08-tempo-por-rota-linha-de-base.txt)):

| Rota | % das requisições | % do tempo de resposta total |
|---|---|---|
| pedidos-do-cliente | 21,8% | **64,5%** |
| pedidos-por-status | 10,7% | 15,8% |
| vendas-por-dia | 6,8% | 8,1% |
| top-produtos | 1,5% | 4,4% |
| cliente-por-email | 17,9% | 4,1% |
| busca-produtos | 16,2% | 1,9% |
| cliente | 25,2% | 1,4% |

**Sozinha, sem carga, a consulta mais simples é rápida.** Buscar um cliente pela chave leva 0,044 ms no banco ([04a](saidas/04a-explain-cliente.txt)), mas a rota `/clientes/:id` teve mediana de ~300 ms sob carga ([resumo da execução 3](../resultados/20261109-203226-00-linha-de-base/resumo.txt)). Quase todo esse tempo é espera: pela conexão e por uma CPU ocupada com as consultas pesadas das outras rotas.

## Problemas encontrados

### P1. Faltam índices nas colunas usadas para buscar e juntar tabelas

**Fatos**
- O banco tem só 4 índices, um por chave primária ([01](saidas/01-estrutura-e-indices.txt)). As chaves estrangeiras `pedidos.cliente_id` e `itens_pedido.pedido_id` não têm índice. O PostgreSQL não cria esse índice automaticamente ([documentação, 5.4.5 Foreign Keys](https://www.postgresql.org/docs/16/ddl-constraints.html#DDL-CONSTRAINTS-FK)).
- Desde que o banco foi criado, `itens_pedido` foi lida inteira 2.011 vezes, somando 1,46 bilhão de linhas lidas, e quase nunca por índice ([03](saidas/03-estatisticas-de-acesso.txt)).
- Buscar os itens de um pedido lê as 1,5 milhão de linhas para devolver 5 (83 ms, *Parallel Seq Scan*) ([04c2](saidas/04c2-explain-pedidos-do-cliente-itens.txt)). Buscar os pedidos de um cliente lê os 500 mil pedidos para devolver 5 (44 ms) ([04c1](saidas/04c1-explain-pedidos-do-cliente-pedidos.txt)).
- Buscar cliente por e-mail com `lower(email)` lê os 100 mil clientes (41 ms) ([04b](saidas/04b-explain-cliente-por-email.txt)), contra 0,044 ms pela chave ([04a](saidas/04a-explain-cliente.txt)).
- Contar os pedidos de um status lê a tabela `pedidos` inteira (93 ms) ([04d1](saidas/04d1-explain-pedidos-por-status-contagem.txt)).

**Hipótese de causa:** sem índice em `itens_pedido.pedido_id`, `pedidos.cliente_id`, `lower(clientes.email)` e `pedidos (status, criado_em)`, cada uma dessas consultas lê a tabela inteira, e é isso que satura a única CPU do banco.

### P2. A rota de pedidos do cliente faz uma consulta por pedido e outra por item (N+1)

**Fatos**
- O código busca o cliente, depois os pedidos, depois os itens de cada pedido e depois o produto de cada item, um por vez ([`api/src/rotas.js:66-89`](../api/src/rotas.js)).
- Para o cliente 12345, com 5 pedidos e 25 itens, isso dá 32 consultas por requisição, e a contagem de conexões medida foi 32,3 por requisição ([05](saidas/05-conexoes-por-requisicao.txt)).
- Sem carga, essa rota leva ~0,7 s ([05](saidas/05-conexoes-por-requisicao.txt)). Sob carga, a mediana passou de 17 s em todas as medições da linha de base, e a rota respondeu por 64,5% do tempo total ([08](saidas/08-tempo-por-rota-linha-de-base.txt)).

**Hipótese de causa:** o número de idas ao banco cresce com o histórico do cliente (2 + pedidos + itens), e cada ida dos itens ainda lê a tabela inteira (P1).

### P3. A API abre uma conexão nova para cada consulta

**Fatos**
- `consultar()` cria um `Client`, conecta, faz uma consulta e desconecta, sem reaproveitar a conexão ([`api/src/db.js:10-19`](../api/src/db.js)).
- Com a mesma consulta da rota `/clientes/:id`, o pgbench fez ~8.100 consultas/s reaproveitando a conexão e ~233/s abrindo uma nova a cada consulta. A latência média subiu de 0,12 ms para 4,3 ms, com 2,7 ms só para conectar ([06](saidas/06-custo-de-conexao-pgbench.txt)).
- O PostgreSQL cria um processo novo para cada conexão ([documentação, 52.2 How Connections Are Established](https://www.postgresql.org/docs/16/connect-estab.html)).

**Hipótese de causa:** conectar a cada consulta soma alguns milissegundos e um processo novo do banco por consulta, o que atrasa todas as rotas e gasta CPU do banco. O efeito é maior na rota com 32 consultas (P2).

### P4. A paginação de pedidos por status ordena centenas de milhares de linhas em disco

**Fatos**
- Para montar a página 500 (OFFSET 9980), o banco lê os 500 mil pedidos, ordena os ~300 mil do status *pago* em disco (*external merge*, ~90 MB somando os 3 processos) e descarta 9.980 linhas para devolver 20 (319 ms) ([04d2](saidas/04d2-explain-pedidos-por-status-pagina.txt)).
- A ordenação vai para o disco porque `work_mem` está no valor de fábrica, 4 MB ([02](saidas/02-configuracao-postgres.txt)), e o `SELECT *` leva junto a coluna `observacoes`, que a rota não devolve (linhas de 299 bytes no plano; [`api/src/rotas.js:113-127`](../api/src/rotas.js)).
- A mesma requisição faz uma segunda leitura completa da tabela só para contar (P1, [04d1](saidas/04d1-explain-pedidos-por-status-contagem.txt)).

**Hipótese de causa:** sem um índice na ordem `(status, criado_em, id)`, cada página obriga o banco a ordenar o status inteiro, e o OFFSET faz o custo crescer com o número da página.

### P5. O relatório de vendas por dia lê as duas tabelas inteiras e manda dados que a API não usa

**Fatos**
- O filtro `p.criado_em::date BETWEEN ...` aplica uma conversão sobre a coluna. O plano lê `pedidos` e `itens_pedido` inteiras e junta as duas (361 ms para 7 dias) ([04f](saidas/04f-explain-vendas-por-dia.txt)).
- A consulta manda 12.922 linhas para a API, incluindo 3,4 MB só da coluna `observacoes`, que a API nunca usa. A soma por dia é feita depois, em JavaScript ([04f](saidas/04f-explain-vendas-por-dia.txt), [`api/src/rotas.js:158-184`](../api/src/rotas.js)).

**Hipótese de causa:** sem índice em `criado_em` e com a conversão aplicada à coluna, o banco não consegue ler só o período pedido, e a agregação fora do banco multiplica o volume que trafega até a API.

### P6. O relatório de produtos mais vendidos recalcula tudo a cada chamada

**Fatos**
- Cada chamada junta e soma ~1,35 milhão de itens de pedidos não cancelados (450 mil linhas em cada um dos 3 processos), em 1,5 s sem carga ([04g](saidas/04g-explain-top-produtos.txt)).
- A aplicação só lê: nenhuma rota grava dados ([`api/src/rotas.js`](../api/src/rotas.js)), então o resultado é o mesmo em todas as chamadas.

**Hipótese de causa:** o relatório refaz do zero, sobre todos os itens, um cálculo cujo resultado não muda entre as chamadas.

### P7. Os parâmetros do banco são os de fábrica, não os do container

**Fatos** ([02](saidas/02-configuracao-postgres.txt))
- `shared_buffers` = 128 MB (16384 × 8 kB), para um banco de 301 MB ([01](saidas/01-estrutura-e-indices.txt)). Em média, 81% das páginas vieram desse cache ([03](saidas/03-estatisticas-de-acesso.txt)). As outras podem ter vindo do cache do sistema operacional, e não do disco: o PostgreSQL não distingue os dois casos.
- `effective_cache_size` = 4 GB (524288 × 8 kB), mas o container tem 512 MB.
- `max_parallel_workers_per_gather` = 2. Vários planos usam 2 processos auxiliares ([04c1](saidas/04c1-explain-pedidos-do-cliente-pedidos.txt), [04d2](saidas/04d2-explain-pedidos-por-status-pagina.txt), [04g](saidas/04g-explain-top-produtos.txt)), mas o container só tem 1 CPU.
- `work_mem` = 4 MB, o que leva a ordenação da P4 para o disco.

**Hipótese de causa (mais fraca que as anteriores):** com 1 CPU, os processos paralelos disputam o mesmo núcleo em vez de acelerar a consulta, e o planejador escolhe planos supondo mais memória do que o container tem. Isso precisa ser medido, porque pode não fazer diferença depois de resolver P1 a P6.

### P8. A API grava no log a resposta inteira de cada requisição

**Fatos**
- O middleware de [`api/src/server.js:7-21`](../api/src/server.js) converte o corpo de cada resposta em JSON uma segunda vez, só para o log.
- Em ~1.000 requisições, o log da API chegou a 1,17 MB, com linhas de até 6,3 KB ([07](saidas/07-log-da-api.txt)).

**Hipótese de causa:** é um custo de armazenamento e de CPU da API que cresce com o tamanho das respostas, mas hoje não é o gargalo (a API usa ~7% de CPU). Prioridade baixa para o tempo de resposta. Pode ser relevante para o custo.

## Verificado e descartado

- **JIT do PostgreSQL:** está ligado (`jit = on`), mas nenhum dos planos o usou ([04g](saidas/04g-explain-top-produtos.txt) e os demais 04*). Não é causa.
- **Recursos da API:** CPU ~7% de 0,5 CPU e memória ~30 MiB de 256 MiB ([recursos](../resultados/20261109-203226-00-linha-de-base/recursos.txt)). A API não é o gargalo e tem folga, o que é uma possível economia a avaliar depois.
- **Busca de produtos:** lê os 20 mil produtos com `ILIKE '%termo%'`, mas leva 12 ms e só 1,9% do tempo total ([04e](saidas/04e-explain-busca-produtos.txt), [08](saidas/08-tempo-por-rota-linha-de-base.txt)). Não é prioridade agora, embora a importância relativa dela possa crescer depois que as outras rotas melhorarem.

## Limites deste diagnóstico

- Os planos (04*) e os tempos de [05](saidas/05-conexoes-por-requisicao.txt) foram medidos **sem carga**, com um valor de parâmetro por rota. Sob carga, os tempos são muito maiores por causa da disputa pela CPU.
- A contagem de conexões de [05](saidas/05-conexoes-por-requisicao.txt) inclui o ruído do healthcheck do compose (`pg_isready` a cada 5 s), por isso os valores ficam um pouco acima dos inteiros esperados.
- As estatísticas acumuladas de [03](saidas/03-estatisticas-de-acesso.txt) incluem a geração dos dados, o contrato, as medições e as execuções deste script. Elas servem para mostrar proporção, não para contar requisições.
- Nenhuma hipótese foi testada ainda. Cada uma será confirmada ou derrubada por uma mudança medida com o `medir.sh` (etapa 04).
