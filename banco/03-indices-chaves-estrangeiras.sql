-- Experimento 01: índices B-tree nas chaves estrangeiras usadas como filtro.
--
-- Diagnóstico (P1): a busca de itens por pedido_id e a de pedidos por
-- cliente_id liam a tabela inteira (Seq Scan), porque o PostgreSQL só cria
-- índice automático para a chave primária, não para a chave estrangeira.
-- Fonte: documentação do PostgreSQL 16, seção 5.4.5 (Foreign Keys).
--
-- Roda depois do 02-dados.sql, então cada índice é construído uma vez,
-- com os dados já carregados.

CREATE INDEX itens_pedido_pedido_id_idx ON itens_pedido (pedido_id);
CREATE INDEX pedidos_cliente_id_idx ON pedidos (cliente_id);
