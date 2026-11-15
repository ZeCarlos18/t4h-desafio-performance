-- Experimento 04: índice de expressão para a busca de cliente por e-mail.
--
-- Diagnóstico (P1): GET /clientes?email= filtra por lower(email) = lower($1),
-- e um índice comum em email não serve para essa expressão; a busca lia os
-- 100 mil clientes (Seq Scan) para achar 1. Um índice sobre lower(email) é
-- usado por exatamente essa condição.
-- Fonte: documentação do PostgreSQL 16, seção 11.7 (Indexes on Expressions).
--
-- Sem UNIQUE: o índice só acelera a busca e não muda nenhuma regra dos dados.

CREATE INDEX clientes_lower_email_idx ON clientes (lower(email));
