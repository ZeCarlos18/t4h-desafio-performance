// Quanto do tempo de resposta total cada rota consumiu nas medições indicadas.
// Lê o resumo-k6.json gerado pelo medir.sh (sem editar nada) e soma, por rota, requisições × tempo médio.
//
//   docker run --rm -v "$PWD":/w -w /w node:20.18.0-alpine \
//     node diagnostico/tempo-por-rota.js resultados/*-00-linha-de-base

const fs = require('fs');
const path = require('path');

const pastas = process.argv.slice(2);
if (pastas.length === 0) {
  console.error('uso: node diagnostico/tempo-por-rota.js resultados/<pasta> [...]');
  process.exit(2);
}

const porRota = new Map();
for (const pasta of pastas) {
  const resumo = JSON.parse(fs.readFileSync(path.join(pasta, 'resumo-k6.json'), 'utf8'));
  for (const [nome, metrica] of Object.entries(resumo.metrics)) {
    const rota = /^http_req_duration\{rota:(.+)\}$/.exec(nome);
    if (!rota) continue;
    const acumulado = porRota.get(rota[1]) || { requisicoes: 0, tempo_ms: 0 };
    acumulado.requisicoes += metrica.values.count;
    acumulado.tempo_ms += metrica.values.count * metrica.values.avg;
    porRota.set(rota[1], acumulado);
  }
}

const total = [...porRota.values()].reduce((soma, r) => soma + r.tempo_ms, 0);
const linhas = [...porRota.entries()].sort(([, a], [, b]) => b.tempo_ms - a.tempo_ms);

console.log(`# Tempo de resposta acumulado por rota, somando ${pastas.length} medição(ões):`);
for (const pasta of pastas) console.log(`#   ${pasta}`);
console.log('');
console.log(`${'rota'.padEnd(20)} ${'requisicoes'.padStart(11)} ${'pct_requisicoes'.padStart(15)} ${'tempo_total_s'.padStart(13)} ${'pct_do_tempo'.padStart(12)}`);
const totalRequisicoes = [...porRota.values()].reduce((soma, r) => soma + r.requisicoes, 0);
for (const [rota, r] of linhas) {
  console.log(
    `${rota.padEnd(20)} ${String(r.requisicoes).padStart(11)} ${(100 * r.requisicoes / totalRequisicoes).toFixed(1).padStart(14)}% ` +
    `${(r.tempo_ms / 1000).toFixed(1).padStart(13)} ${(100 * r.tempo_ms / total).toFixed(1).padStart(11)}%`,
  );
}
