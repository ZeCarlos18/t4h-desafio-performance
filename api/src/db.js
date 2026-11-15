const { Pool } = require('pg');

const config = {
  host: process.env.DB_HOST || 'localhost',
  port: Number(process.env.DB_PORT || 5432),
  user: process.env.DB_USER || 'loja',
  database: process.env.DB_NAME || 'loja',
};

// Um pool só para a aplicação inteira: as conexões ficam abertas e são
// reaproveitadas, em vez de abrir e fechar uma conexão (e um processo no
// PostgreSQL) a cada consulta. Tamanho padrão do pg.Pool: max = 10.
// Fonte: https://node-postgres.com/features/pooling e https://node-postgres.com/apis/pool
const pool = new Pool(config);

// Uma conexão parada no pool ainda pode receber erro do banco (queda, rede).
// A documentação recomenda este listener: sem ele, o Node trata o evento como
// erro não capturado e pode encerrar o processo.
pool.on('error', (erro) => {
  console.error('erro em conexão ociosa do pool:', erro.message);
});

async function consultar(sql, parametros = []) {
  const resultado = await pool.query(sql, parametros);
  return resultado.rows;
}

module.exports = { consultar };
