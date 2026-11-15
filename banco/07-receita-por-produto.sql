-- Experimento 07: receita por produto pré-calculada (view materializada).
--
-- Diagnóstico (P6): GET /relatorios/top-produtos juntava os 1,5 milhão de
-- itens com pedidos e produtos e agrupava tudo a cada chamada (~1,5 s), para
-- devolver no máximo 50 linhas. A view materializada guarda o resultado desse
-- agrupamento como uma tabela, e a rota passa a ler só as primeiras linhas.
-- Fonte: documentação do PostgreSQL 16, seção 41.3 (Materialized Views).
--
-- A consulta é a mesma que a rota fazia (mesmos filtros, junções e somas, e
-- portanto os mesmos tipos), só que sem ORDER BY e LIMIT, que ficam na rota.
-- Custo: o resultado só muda com REFRESH MATERIALIZED VIEW. Nesta aplicação
-- nenhuma rota grava dados; se a loja passasse a gravar pedidos, seria preciso
-- atualizar a view (por exemplo, de tempos em tempos).

CREATE MATERIALIZED VIEW receita_por_produto AS
SELECT pr.id, pr.nome, pr.categoria,
       sum(i.quantidade) AS unidades,
       sum(i.quantidade * i.preco_unitario_centavos) AS receita_centavos
  FROM itens_pedido i
  JOIN pedidos p ON p.id = i.pedido_id
  JOIN produtos pr ON pr.id = i.produto_id
 WHERE p.status <> 'cancelado'
 GROUP BY pr.id, pr.nome, pr.categoria
WITH DATA;

-- Na mesma ordem do ORDER BY da rota, para o LIMIT ler só as primeiras
-- linhas do índice, sem ordenar as 20 mil (seção 11.4, Indexes and ORDER BY).
CREATE INDEX receita_por_produto_receita_id_idx ON receita_por_produto (receita_centavos DESC, id);
