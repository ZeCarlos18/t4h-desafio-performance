const express = require('express');
const rotas = require('./rotas');

const app = express();
const porta = Number(process.env.PORT || 3000);

app.use((req, res, next) => {
  const inicio = Date.now();
  const enviarJson = res.json.bind(res);
  res.json = (corpo) => {
    // Só os dados da requisição, sem o corpo da resposta: antes cada resposta
    // era convertida em texto duas vezes (uma para o log, outra para enviar)
    // e o log crescia ~1,2 KB por requisição. A resposta enviada não muda.
    console.log(JSON.stringify({
      metodo: req.method,
      url: req.originalUrl,
      status: res.statusCode,
      duracao_ms: Date.now() - inicio,
    }));
    return enviarJson(corpo);
  };
  next();
});

app.use(rotas);

app.use((req, res) => {
  res.status(404).json({ erro: 'rota nao encontrada' });
});

app.use((erro, req, res, next) => {
  console.error(erro);
  res.status(500).json({ erro: 'erro interno' });
});

app.listen(porta, () => {
  console.log(`API ouvindo na porta ${porta}`);
});
