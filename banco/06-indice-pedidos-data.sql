-- Experimento 06: índice de expressão para o relatório de vendas por dia.
--
-- Diagnóstico (P5): GET /relatorios/vendas-por-dia filtra por
-- p.criado_em::date BETWEEN $1 AND $2, e sem índice o banco lia os 500 mil
-- pedidos para achar os de 7 dias. Um índice sobre a mesma expressão
-- (criado_em::date) é usado por esse filtro sem mudar a consulta da API.
-- Fonte: documentação do PostgreSQL 16, seção 11.7 (Indexes on Expressions).
--
-- criado_em é timestamp sem fuso, e a conversão timestamp -> date é imutável,
-- requisito para uma expressão de índice (conferido em pg_proc.provolatile).

CREATE INDEX pedidos_criado_em_data_idx ON pedidos ((criado_em::date));
