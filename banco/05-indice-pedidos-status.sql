-- Experimento 05: índice para a listagem de pedidos por status.
--
-- Diagnóstico (P4): GET /pedidos?status=&pagina= filtra por status e ordena
-- por criado_em DESC, id DESC. Sem índice, o banco lia a tabela inteira e
-- ordenava ~300 mil pedidos em disco (external merge) a cada página.
--
-- Com status na frente (igualdade) e as colunas da ordenação em seguida, na
-- mesma direção do ORDER BY, o banco percorre o índice já na ordem pedida e
-- para depois de OFFSET + 20 linhas, sem etapa de ordenação.
-- Fontes: documentação do PostgreSQL 16, seções 11.3 (Multicolumn Indexes) e
-- 11.4 (Indexes and ORDER BY). As linhas do OFFSET continuam sendo percorridas
-- (seção 7.6, LIMIT and OFFSET); trocar a paginação mudaria o contrato.

CREATE INDEX pedidos_status_criado_em_id_idx ON pedidos (status, criado_em DESC, id DESC);
