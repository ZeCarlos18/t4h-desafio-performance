# Experimentos (etapa 04)

Cada mudança tem o próprio commit, foi aplicada, passou no verificador de contrato e foi medida 3 vezes com `scripts/medir.sh`, sempre com os parâmetros padrão: 20 usuários virtuais, 60 s, aquecimento de 15 s e semente 42. A comparação usa a **mediana das 3 execuções**.

## Como os números foram calculados

- As medianas saem do [`analise/medianas.js`](analise/medianas.js), que só lê os arquivos de `resultados/`. Para repetir: `node analise/medianas.js <rotulo-antes> <rotulo-depois>`. A saída de cada experimento fica salva em `analise/saidas/`, sem edição.
- **Requisições/s e p95 geral** vêm do `resumo-k6.json`.
- **CPU e memória** vêm das amostras do `recursos.csv`.
- **Por que não usar os máximos do `recursos.txt`:** o `awk` do `scripts/medir.sh` compara os valores como texto, então "9.86" é considerado maior que "32.21". Por isso as colunas `cpu_max` e `mem_max` podem sair erradas; um exemplo é a API em `resultados/20261111-202249-01-indices-fk/recursos.txt`, com média de 14,5% e "máximo" de 9,9%. As médias de lá estão certas. O script não foi corrigido, porque o desafio proíbe editar `scripts/`; os máximos foram recalculados a partir das amostras.

## Resumo

O **antes** de cada linha é a mudança anterior; o da primeira é a linha de base (`00-linha-de-base`). As pastas de resultados estão listadas no arquivo de medianas de cada experimento.

| # | Mudança | Fonte | Status | Antes (req/s · p95) | Depois (req/s · p95) | Medianas e pastas | Conclusão |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 01 | Índices B-tree em `itens_pedido(pedido_id)` e `pedidos(cliente_id)` | [pesquisa.md](pesquisa.md): O1, A1, A3 | Aplicada e medida | 2,96 · 22.484 ms | 5,57 · 10.906 ms | [01-indices-fk-medianas.md](analise/saidas/01-indices-fk-medianas.md) | Vazão +88%, p95 geral −51%. O banco continua com cerca de 97% de 1 CPU, então o gargalo mudou de lugar |
| 02 | Fim do N+1 em `pedidos-do-cliente`: itens de todos os pedidos numa consulta, com JOIN em produtos | [pesquisa.md](pesquisa.md): A2, A3 | Aplicada e medida | 5,57 · 10.906 ms | 7,05 · 13.370 ms | [02-fim-n-mais-1-medianas.md](analise/saidas/02-fim-n-mais-1-medianas.md) | p95 da rota −81% e conexões por requisição de 32,3 para 3,1. Vazão +26,5%, mas o p95 geral subiu 22,6%, porque o tempo liberado virou mais requisições nas rotas pesadas (modelo fechado, O17) |
| 03 | `pg.Pool` na API (tamanho padrão, `max` = 10) no lugar de uma conexão nova por consulta | [pesquisa.md](pesquisa.md): O2, O12, O13 | Aplicada e medida | 7,05 · 13.370 ms | 8,23 · 7.431 ms | [03-pool-conexoes-medianas.md](analise/saidas/03-pool-conexoes-medianas.md) | Vazão +16,7% e p95 geral −44,4%, mas a mediana subiu 58%: as rotas pesadas ficaram mais rápidas e as leves, mais lentas sob carga. Hipótese: fila no pool de 10 conexões |
| 04 | Índice de expressão em `clientes(lower(email))` | [pesquisa.md](pesquisa.md): O5 | Aplicada e medida | 8,23 · 7.431 ms | 8,70 · 7.470 ms | [04-indice-email-medianas.md](analise/saidas/04-indice-email-medianas.md) | Consulta de 40,7 ms para 1,4 ms e p95 da rota −23,8%. No geral, ganho pequeno (vazão +5,7%, mediana −15,3%, p95 igual), dentro da variação entre execuções |
| 05 | Índice `pedidos(status, criado_em DESC, id DESC)`, mantendo a paginação por OFFSET | [pesquisa.md](pesquisa.md): O3, O4, O6, M1 | Aplicada e medida | 8,70 · 7.470 ms | 15,68 · 3.596 ms | [05-indice-status-medianas.md](analise/saidas/05-indice-status-medianas.md) | Página 500 de 318,6 ms para 10,8 ms, sem ordenação em disco. Vazão +80,3%, p95 geral −51,9%, mediana −42,7%. Todas as rotas melhoraram, menos `top-produtos`, que agora é o gargalo |

## 01. Índices nas chaves estrangeiras

- **Hipótese** ([pesquisa.md](pesquisa.md), plano de experimentos): criar índices em `itens_pedido(pedido_id)` e `pedidos(cliente_id)` deve reduzir o p95 geral, principalmente o de `pedidos-do-cliente`, porque essas consultas deixam de ler a tabela inteira.
- **Mudança:** [`banco/03-indices-chaves-estrangeiras.sql`](banco/03-indices-chaves-estrangeiras.sql), commit `08f12ba`. O banco foi recriado do zero com `docker compose down -v && docker compose up -d --build`.
- **Contrato:** mantido, com 42 de 42 respostas iguais, nas 3 medições (`contrato.txt` de cada pasta).

**Efeito no banco** ([evidências](analise/saidas/01-indices-fk-evidencias.txt), mesmas consultas e parâmetros do diagnóstico):

| Consulta | Antes (diagnóstico) | Depois |
| --- | --- | --- |
| Pedidos do cliente 12345 | Parallel Seq Scan, 43,6 ms ([04c1](diagnostico/saidas/04c1-explain-pedidos-do-cliente-pedidos.txt)) | Index Scan, 0,80 ms |
| Itens de um pedido | Parallel Seq Scan, 83,4 ms ([04c2](diagnostico/saidas/04c2-explain-pedidos-do-cliente-itens.txt)) | Index Scan, 0,68 ms |

**Custo:** os índices ocupam 21 MB (`itens_pedido_pedido_id_idx`) e 5,6 MB (`pedidos_cliente_id_idx`). O banco foi de 301 MB ([diagnóstico](diagnostico/saidas/01-estrutura-e-indices.txt)) para 328 MB. A aplicação só lê, então a escrita mais lenta não pesa aqui.

**Carga** (mediana de 3, [arquivo completo](analise/saidas/01-indices-fk-medianas.md)):

| Métrica | Linha de base | 01-indices-fk | Variação |
| --- | ---: | ---: | ---: |
| Requisições/s | 2,96 | 5,57 | +88,3% |
| p95 geral | 22.484 ms | 10.906 ms | −51,5% |
| Mediana geral | 1.400 ms | 1.191 ms | −14,9% |
| p95 `pedidos-do-cliente` | 25.303 ms | 10.556 ms | −58,3% |
| CPU média do banco (100% = 1 CPU) | 94,3% | 96,7% | +2,6% |
| Memória média da API | 29,4 MiB | 92,2 MiB | +213,5% |

**Conclusão:**

- **A hipótese se confirmou:** a vazão quase dobrou e o p95 caiu pela metade, com o maior ganho na rota prevista.
- **O banco continua saturado,** em cerca de 97% da sua CPU. As consultas de pedidos e itens ficaram mais de 50 vezes mais rápidas, mas o p95 de `pedidos-do-cliente` ainda é de 10,6 s. Como toda rota divide a mesma CPU do banco, o tempo que sobra é sobretudo fila atrás das consultas pesadas (`top-produtos`, `vendas-por-dia`, `pedidos-por-status`) e das 32 conexões por requisição (P2 e P3).
- **O p95 de `vendas-por-dia` subiu, de 11,3 s para 25,5 s.** São poucas amostras (14 e 27 requisições por medição), e o README avisa que esses números oscilam muito. Não tiro conclusão por rota com tão poucas requisições; a consulta dessa rota não usa os índices novos.
- **A memória média da API subiu** junto com a vazão, mas segue abaixo de 120 MiB de 256 MiB. Hipótese não verificada: mais respostas por segundo significam mais objetos e mais `JSON.stringify` no log (P8), que serão testados no experimento 09.

## 02. Fim do N+1 na rota de pedidos do cliente

- **Hipótese** ([pesquisa.md](pesquisa.md), plano de experimentos): buscar os itens de todos os pedidos numa consulta só deve reduzir o p95 de `pedidos-do-cliente`, porque a rota passa de 1 consulta por pedido e 1 por item para 3 consultas no total.
- **Fonte:** Chen et al. (A2) chamam esse padrão de *one-by-one processing*.
- **Antes:** o experimento 01 (`01-indices-fk`).
- **Mudança:** [`api/src/rotas.js`](api/src/rotas.js), commit `07a5b2f`. Os itens vêm de uma consulta com `pedido_id = ANY($1)` e `JOIN produtos`, ordenada por `pedido_id, id`, e são agrupados por pedido no JavaScript. A ordem dos itens, o total e os campos continuam os mesmos. A consulta dos pedidos não mudou. Só a API foi reconstruída (`docker compose up -d --build`).
- **Contrato:** mantido, com 42 de 42 respostas iguais, nas 3 medições.

**Efeito na rota, sem carga** ([conexões depois](analise/saidas/02-fim-n-mais-1-conexoes.txt), [antes](diagnostico/saidas/05-conexoes-por-requisicao.txt); 10 requisições a `GET /clientes/12345/pedidos`):

| Medida | Antes (diagnóstico) | Depois |
| --- | ---: | ---: |
| Conexões abertas no banco por requisição | 32,3 | 3,1 |
| Tempo médio da requisição | 0,700 s | 0,022 s |
| Tamanho da resposta | 3.365 bytes | 3.365 bytes |

**Carga** (mediana de 3, [arquivo completo](analise/saidas/02-fim-n-mais-1-medianas.md)):

| Métrica | 01-indices-fk | 02-fim-n-mais-1 | Variação |
| --- | ---: | ---: | ---: |
| Requisições/s | 5,57 | 7,05 | +26,5% |
| Mediana geral | 1.191 ms | 893 ms | −25,0% |
| p95 geral | 10.906 ms | 13.370 ms | +22,6% |
| p95 `pedidos-do-cliente` | 10.556 ms | 1.970 ms | −81,3% |
| CPU média do banco (100% = 1 CPU) | 96,7% | 90,8% | −6,1% |
| CPU média da API | 14,3% | 11,2% | −21,9% |
| Memória média da API | 92,2 MiB | 102 MiB | +11,0% |

**Erros:** a mediana é 0%. A execução 3 (`resultados/20261115-092432-02-fim-n-mais-1`) teve 1 erro em 480 requisições (0,21%). Foi uma requisição de `top-produtos` que chegou a 60.000 ms, o *timeout* fixo do `carga/teste-carga.js`; está registrada no `resumo-k6.json` daquela pasta. A rota `top-produtos` não foi alterada neste experimento. A execução não foi descartada, porque a regra é comparar a mediana, não a melhor execução.

**Conclusão:**

- **A hipótese se confirmou para a rota.** O p95 de `pedidos-do-cliente` caiu 81%, e cada requisição abre 3 conexões em vez de 32. Somado ao experimento 01, o p95 dessa rota foi de 25.303 ms na linha de base para 1.970 ms.
- **O p95 geral piorou, e isso é efeito da forma de medir, não da rota alterada.** O `medir.sh` usa um número fixo de 20 usuários sem pausa, o modelo fechado do k6. Nele, a próxima requisição só sai quando a anterior termina (fonte O17), então o tempo que a rota de pedidos deixou de gastar virou **mais requisições nas rotas pesadas**:

  | Rota | Requisições (01 → 02) | p95 (01 → 02) |
  | --- | --- | --- |
  | `pedidos-por-status` | 46 → 64 | +35% |
  | `top-produtos` | 4 → 6 | +42% |
  | `busca-produtos` | 59 → 75 | +31% |

  Elas disputam a mesma CPU do banco e formam a cauda do p95. A vazão subiu 26,5%, e a CPU do banco caiu de 96,7% para 90,8% mesmo atendendo mais requisições, porque abrir conexão custa um processo novo no servidor (O2).
- **O gargalo agora são as consultas pesadas:** `top-produtos`, `vendas-por-dia` e a paginação de `pedidos-por-status`, que são os experimentos 05 a 07. As conexões novas das outras rotas são o experimento 03.
- **Contra a linha de base,** os dois experimentos somados levam a vazão de 2,96 para 7,05 req/s (+138%) e o p95 geral de 22.484 para 13.370 ms (−40,5%) ([arquivo](analise/saidas/02-fim-n-mais-1-vs-linha-de-base-medianas.md)).

## 03. Pool de conexões na API

- **Hipótese** ([pesquisa.md](pesquisa.md), plano de experimentos): usar um `pg.Pool` deve aumentar as requisições/s em todas as rotas, porque cada consulta deixa de pagar uma conexão nova e um processo novo no PostgreSQL (O2). O diagnóstico mediu 2,7 ms só para conectar ([06](diagnostico/saidas/06-custo-de-conexao-pgbench.txt)).
- **Antes:** o experimento 02 (`02-fim-n-mais-1`).
- **Mudança:** [`api/src/db.js`](api/src/db.js), commit `8c9d7e0`. Um `pg.Pool` para a aplicação inteira, com o tamanho padrão (`max` = 10) e o listener de `error` que a documentação recomenda (O12, O13). O tamanho do pool não foi ajustado, para mudar uma coisa só. A aplicação não usa transações, o único caso em que a documentação desaconselha `pool.query`.
- **Contrato:** mantido, com 42 de 42 respostas iguais, nas 3 medições.

**Sem carga** ([depois](analise/saidas/03-pool-conexoes-conexoes.txt), [antes](analise/saidas/02-fim-n-mais-1-conexoes.txt); 10 requisições seguidas de cada rota): as conexões novas por requisição caíram para 0,1 a 0,3, que é o ruído do próprio contador e do healthcheck, porque as conexões passaram a ser reaproveitadas.

| Rota (sem carga) | Tempo médio antes | Tempo médio depois |
| --- | ---: | ---: |
| `GET /clientes/12345` | 7,4 ms | 2,4 ms |
| `GET /clientes/12345/pedidos` | 21,8 ms | 3,7 ms |
| `GET /produtos/busca?q=cadeira` | 21,8 ms | 14,6 ms |

**Carga** (mediana de 3, [arquivo completo](analise/saidas/03-pool-conexoes-medianas.md)):

| Métrica | 02-fim-n-mais-1 | 03-pool-conexoes | Variação |
| --- | ---: | ---: | ---: |
| Requisições/s | 7,05 | 8,23 | +16,7% |
| p95 geral | 13.370 ms | 7.431 ms | −44,4% |
| Mediana geral | 893 ms | 1.411 ms | +58,0% |
| Erros | 0% | 0% | - |
| CPU média do banco (100% = 1 CPU) | 90,8% | 91,6% | +0,9% |
| Memória média da API | 102 MiB | 88,5 MiB | −13,5% |

**Por rota, o efeito se dividiu em dois grupos:**

| Grupo | Rota | p95 (02 → 03) |
| --- | --- | --- |
| Pesadas: melhoraram | `top-produtos` | −50,7% |
| | `vendas-por-dia` | −50,1% |
| | `pedidos-por-status` | −35,1% |
| Leves: pioraram | `cliente` | +214% |
| | `pedidos-do-cliente` | +150% |
| | `busca-produtos` | +37,6% |

**Conclusão:**

- **A hipótese se confirmou em parte.** Sem carga, todas as rotas ficaram mais rápidas. Sob carga, a vazão subiu 16,7% e o p95 geral caiu 44,4%, mas a mediana piorou 58%.
- **Hipótese para a divisão, ainda não verificada:** o pool limita o banco a 10 consultas ao mesmo tempo, e os 20 usuários virtuais disputam essas 10 conexões.
  - **Antes,** cada consulta tinha a sua conexão, então até 20 processos dividiam 1 CPU, e uma consulta leve rodava intercalada com as pesadas.
  - **Agora,** com menos consultas simultâneas, as pesadas terminam mais rápido, por disputarem a CPU com menos processos. Mas uma requisição leve que chega com as 10 conexões ocupadas **espera na fila do pool**, dentro da API, até uma consulta pesada liberar a conexão.
  - **Para testar,** seria preciso medir a fila do pool (`pool.waitingCount`, O13) durante a carga e variar o `max`. Isso fica como teste futuro ou como experimento próprio.
- **A mudança fica.** Ela melhorou as duas métricas principais da comparação, vazão e p95, sem custo de recurso: a memória da API caiu e a CPU do banco ficou igual. A mediana pior é o custo, e o experimento confirma que **o limite agora são as consultas pesadas**, que ocupam as conexões. Os experimentos 05 a 07 atacam justamente essas consultas.
- **Contra a linha de base,** os três experimentos somados levam a vazão de 2,96 para 8,23 req/s (+178%) e o p95 geral de 22.484 para 7.431 ms (−66,9%). A mediana ficou praticamente igual, de 1.400 para 1.411 ms ([arquivo](analise/saidas/03-pool-conexoes-vs-linha-de-base-medianas.md)).

## 04. Índice para a busca por e-mail

- **Hipótese** ([pesquisa.md](pesquisa.md), plano de experimentos): um índice sobre `lower(email)` deve reduzir o p95 de `cliente-por-email`, porque a busca deixa de ler os 100 mil clientes.
- **Antes:** o experimento 03 (`03-pool-conexoes`).
- **Mudança:** [`banco/04-indice-email.sql`](banco/04-indice-email.sql), commit `00bd026`. É um índice B-tree sobre a expressão `lower(email)`, exatamente a que a rota usa no `WHERE` (O5). Não é `UNIQUE`, para não mudar nenhuma regra dos dados. O banco foi recriado do zero (`docker compose down -v && docker compose up -d --build`).
- **Contrato:** mantido, com 42 de 42 respostas iguais, nas 3 medições, inclusive nos casos com e-mail em maiúsculas.

**Efeito no banco** ([evidências](analise/saidas/04-indice-email-evidencias.txt), mesma consulta e e-mail do diagnóstico):

| Consulta | Antes ([04b](diagnostico/saidas/04b-explain-cliente-por-email.txt)) | Depois |
| --- | --- | --- |
| `lower(email) = lower('cliente12345@exemplo.com')` | Seq Scan, 99.999 linhas descartadas, 40,7 ms | Bitmap Index Scan em `clientes_lower_email_idx`, 1,35 ms |
| A mesma busca com `CLIENTE10@EXEMPLO.COM` | - | Bitmap Index Scan, 0,07 ms |

**Custo:** o índice ocupa 4,8 MB, e o banco foi de 328 MB para 332 MB.

**Carga** (mediana de 3, [arquivo completo](analise/saidas/04-indice-email-medianas.md)):

| Métrica | 03-pool-conexoes | 04-indice-email | Variação |
| --- | ---: | ---: | ---: |
| Requisições/s | 8,23 | 8,70 | +5,7% |
| Mediana geral | 1.411 ms | 1.195 ms | −15,3% |
| p95 geral | 7.431 ms | 7.470 ms | +0,5% |
| p95 `cliente-por-email` | 2.099 ms | 1.600 ms | −23,8% |
| CPU média do banco (100% = 1 CPU) | 91,6% | 88,8% | −3,0% |
| Erros | 0% | 0% | - |

**Conclusão:**

- **A hipótese se confirmou na rota.** A consulta ficou cerca de 30 vezes mais rápida, de 40,7 para 1,35 ms, e o p95 de `cliente-por-email` caiu 23,8%.
- **No geral, o ganho é pequeno, e eu o trato como incerto.** As requisições/s das três execuções foram de 8,18 a 8,42 no experimento 03 e de 8,38 a 9,18 aqui. As faixas se encostam, e o README avisa que a diferença entre execuções pode passar de 30%.
- **A rota ainda leva 1,6 s no p95,** embora a consulta leve menos de 2 ms. Antes do índice ela custava 41 ms de CPU por requisição; agora quase nada. O que sobra é **espera**: fila no pool e CPU do banco ocupada pelas consultas pesadas (`top-produtos`, de cerca de 1,2 s cada, e `pedidos-por-status`).
- **Observações que esta mudança não explica,** registradas para não esconder nada:
  - A memória média da API caiu de 88,5 para 40,5 MiB, mas a mudança não toca a API, que só foi reiniciada junto com o banco.
  - A memória máxima do banco chegou a 504 MiB, perto do limite de 512 MiB. Isso pesa no experimento 10 (limites menores).
  - O planejador estimou 500 linhas para a busca, e veio 1. Hipótese a verificar: o `ANALYZE` do `02-dados.sql` roda antes de o índice existir, então não há estatística da expressão `lower(email)`. Mesmo assim o índice foi usado.
- **Contra a linha de base,** os quatro experimentos somados levam a vazão de 2,96 para 8,70 req/s (+194%), o p95 geral de 22.484 para 7.470 ms (−66,8%) e a mediana de 1.400 para 1.195 ms (−14,6%) ([arquivo](analise/saidas/04-indice-email-vs-linha-de-base-medianas.md)).

## 05. Índice para a listagem de pedidos por status

- **Hipótese** ([pesquisa.md](pesquisa.md), plano de experimentos): um índice em `(status, criado_em DESC, id DESC)` deve reduzir o p95 de `pedidos-por-status`, porque elimina a ordenação em disco.
- **Antes:** o experimento 04 (`04-indice-email`).
- **Mudança:** [`banco/05-indice-pedidos-status.sql`](banco/05-indice-pedidos-status.sql), commit `5039717`. O `status` vem na frente porque é a igualdade do `WHERE` (O3), e as colunas da ordenação vêm na mesma direção do `ORDER BY` (O4). A paginação por `OFFSET` continua: a *keyset* quebraria o contrato, porque a rota recebe o número da página (M1). O banco foi recriado do zero.
- **Escopo:** a pesquisa também sugeria buscar só as colunas usadas (sem `observacoes`). Ficou de fora para manter uma mudança por commit; é candidata a experimento próprio.
- **Contrato:** mantido, com 42 de 42 respostas iguais, nas 3 medições, inclusive `pagina=15000`, que fica além do fim.

**Efeito no banco** ([evidências](analise/saidas/05-indice-status-evidencias.txt), mesmas consultas e parâmetros do diagnóstico, com `status=pago`):

| Consulta | Antes | Depois |
| --- | --- | --- |
| Contagem por status ([04d1](diagnostico/saidas/04d1-explain-pedidos-por-status-contagem.txt)) | Parallel Seq Scan, 92,9 ms | Parallel Index Only Scan, 33,1 ms |
| Página 500, `OFFSET 9980` ([04d2](diagnostico/saidas/04d2-explain-pedidos-por-status-pagina.txt)) | Seq Scan e ordenação *external merge* em disco (cerca de 90 MB entre os 3 processos), 318,6 ms | Index Scan, sem ordenação, 10,8 ms |
| Página 1000, `OFFSET 19980` (a maior que a carga sorteia) | - | Index Scan, 20,0 ms |

O tempo da página 1000 é quase o dobro da página 500, porque o índice ainda percorre as linhas puladas. É o custo do `OFFSET` que a documentação descreve (O6), e ele continua crescendo com o número da página.

**Custo:** o índice ocupa 21 MB, e o banco foi de 332 MB para 353 MB.

**Carga** (mediana de 3, [arquivo completo](analise/saidas/05-indice-status-medianas.md)):

| Métrica | 04-indice-email | 05-indice-status | Variação |
| --- | ---: | ---: | ---: |
| Requisições/s | 8,70 | 15,68 | +80,3% |
| Mediana geral | 1.195 ms | 684 ms | −42,7% |
| p95 geral | 7.470 ms | 3.596 ms | −51,9% |
| p95 `pedidos-por-status` | 10.069 ms | 3.995 ms | −60,3% |
| p95 `top-produtos` | 21.625 ms | 22.654 ms | +4,8% |
| CPU média do banco (100% = 1 CPU) | 88,8% | 97,6% | +9,9% |
| Memória média do banco | 396 MiB | 433 MiB | +9,5% |
| Erros | 0% | 0% | - |

**Conclusão:**

- **A hipótese se confirmou, e o ganho foi além da rota.** A consulta da página ficou cerca de 30 vezes mais rápida e o p95 de `pedidos-por-status` caiu 60%. A vazão quase dobrou: as três execuções ficaram entre 14,25 e 16,73 req/s, contra 8,38 a 9,18 no experimento 04, então as faixas não se encostam.
- **Todas as outras rotas melhoraram junto**, entre 18% e 46% no p95, sem nenhuma mudança nelas. Antes, cada página ordenava cerca de 300 mil pedidos e gravava dezenas de MB em disco temporário, ocupando CPU do banco e uma conexão do pool por centenas de milissegundos. Com isso liberado, as outras consultas esperam menos.
- **A CPU do banco subiu para 97,6%,** mas agora fazendo quase o dobro de requisições.
- **O novo gargalo é `top-produtos`**, a única rota cujo p95 não caiu (22,7 s). Ela agrega todos os itens a cada chamada, e é o experimento 07.
- **Contra a linha de base,** os cinco experimentos somados levam a vazão de 2,96 para 15,68 req/s (+430%), o p95 geral de 22.484 para 3.596 ms (−84,0%) e a mediana de 1.400 para 684 ms (−51,1%) ([arquivo](analise/saidas/05-indice-status-vs-linha-de-base-medianas.md)).
