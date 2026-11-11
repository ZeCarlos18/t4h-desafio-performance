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
