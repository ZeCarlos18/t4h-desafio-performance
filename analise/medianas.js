// Calcula a mediana das execuções de cada rótulo, a partir dos arquivos
// gerados pelo scripts/medir.sh (resumo-k6.json e recursos.txt), e compara
// cada rótulo com o primeiro. Só lê os arquivos; não altera nada.
//
// Uso: node analise/medianas.js <rotulo-antes> <rotulo-depois> [...]
// Ex.: node analise/medianas.js 00-linha-de-base 01-indices-fk

const fs = require('fs');
const path = require('path');

const PASTA = 'resultados';
const ROTAS = [
  'cliente', 'cliente-por-email', 'pedidos-do-cliente', 'pedidos-por-status',
  'busca-produtos', 'vendas-por-dia', 'top-produtos',
];

function mediana(valores) {
  const v = [...valores].sort((a, b) => a - b);
  const m = Math.floor(v.length / 2);
  return v.length % 2 ? v[m] : (v[m - 1] + v[m]) / 2;
}

function lerExecucao(pasta) {
  const k6 = JSON.parse(fs.readFileSync(path.join(pasta, 'resumo-k6.json'), 'utf8'));
  const m = k6.metrics;
  const dados = {
    req_s: m.http_reqs.values.rate,
    requisicoes: m.http_reqs.values.count,
    mediana_ms: m.http_req_duration.values.med,
    p95_ms: m.http_req_duration.values['p(95)'],
    erros_pct: 100 * m.http_req_failed.values.rate,
  };
  for (const rota of ROTAS) {
    const d = m[`http_req_duration{rota:${rota}}`];
    if (d) {
      dados[`${rota} req`] = d.values.count;
      dados[`${rota} p95_ms`] = d.values['p(95)'];
    }
  }
  // CPU e memória a partir das amostras brutas (recursos.csv). Não usamos as
  // colunas de máximo do recursos.txt: o awk do medir.sh compara os valores
  // como texto ("9.86" > "32.21"), então o máximo pode sair errado. As médias
  // de lá estão certas; aqui recalculamos as duas coisas com números.
  const amostras = {};
  const csv = fs.readFileSync(path.join(pasta, 'recursos.csv'), 'utf8').trim().split('\n').slice(1);
  for (const linha of csv) {
    const [, container, cpu, memoria] = linha.split(',');
    const nome = container.match(/-([a-z0-9]+)-\d+$/);
    if (!nome) continue;
    const usada = memoria.split(' / ')[0];
    const numero = parseFloat(usada);
    const fator = /GiB/.test(usada) ? 1024 : /KiB/.test(usada) ? 1 / 1024 : /MiB/.test(usada) ? 1 : 1 / 1048576;
    (amostras[nome[1]] ||= { cpu: [], mem: [] });
    amostras[nome[1]].cpu.push(parseFloat(cpu));
    amostras[nome[1]].mem.push(numero * fator);
  }
  const media = (v) => v.reduce((a, b) => a + b, 0) / v.length;
  for (const [nome, a] of Object.entries(amostras)) {
    dados[`${nome} cpu_media_pct`] = media(a.cpu);
    dados[`${nome} cpu_max_pct`] = Math.max(...a.cpu);
    dados[`${nome} mem_media_mib`] = media(a.mem);
    dados[`${nome} mem_max_mib`] = Math.max(...a.mem);
  }
  return dados;
}

const rotulos = process.argv.slice(2);
if (rotulos.length === 0) {
  console.error('Uso: node analise/medianas.js <rotulo> [<rotulo> ...]');
  process.exit(1);
}

const resultado = {};
for (const rotulo of rotulos) {
  const pastas = fs.readdirSync(PASTA)
    .filter((p) => p.endsWith(`-${rotulo}`))
    .sort()
    .map((p) => path.join(PASTA, p));
  if (pastas.length === 0) {
    console.error(`Nenhuma pasta para o rótulo ${rotulo}`);
    process.exit(1);
  }
  const execucoes = pastas.map(lerExecucao);
  const medianas = {};
  for (const chave of Object.keys(execucoes[0])) {
    const valores = execucoes.map((e) => e[chave]).filter((x) => x !== undefined);
    medianas[chave] = mediana(valores);
  }
  resultado[rotulo] = { pastas, medianas };
}

const fmt = (x) => (Math.abs(x) >= 100 ? x.toFixed(0) : x.toFixed(2));
const base = rotulos[0];

for (const rotulo of rotulos) {
  console.log(`${rotulo}: ${resultado[rotulo].pastas.length} execuções`);
  for (const p of resultado[rotulo].pastas) console.log(`  ${p}`);
}
console.log('');
console.log(`| métrica (mediana) | ${rotulos.join(' | ')} | variação ${rotulos[rotulos.length - 1]} vs ${base} |`);
console.log(`| --- |${rotulos.map(() => ' ---: |').join('')} ---: |`);
for (const chave of Object.keys(resultado[base].medianas)) {
  const valores = rotulos.map((r) => resultado[r].medianas[chave]);
  const antes = valores[0];
  const depois = valores[valores.length - 1];
  const variacao = antes ? `${((100 * (depois - antes)) / antes).toFixed(1)}%` : '-';
  console.log(`| ${chave} | ${valores.map((v) => (v === undefined ? '-' : fmt(v))).join(' | ')} | ${variacao} |`);
}
