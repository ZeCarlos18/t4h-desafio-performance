// Gera artigo/img/evolucao.svg: requisições/s e p95 geral (mediana de 3
// execuções) da linha de base e de cada experimento.
//
// Não digita nenhum número: lê as tabelas que o analise/medianas.js já gravou
// em analise/saidas/<rotulo>-medianas.md (coluna "depois" de cada experimento;
// a linha de base vem da coluna "antes" do experimento 01).
//
// Uso (dentro da pasta do repositório):
//   docker run --rm --user "$(id -u):$(id -g)" -v "$PWD":/w -w /w node:20.18.0-alpine \
//     node analise/grafico-evolucao.js

const fs = require('fs');
const path = require('path');

const EXPERIMENTOS = [
  ['01-indices-fk', '01 índices FK'],
  ['02-fim-n-mais-1', '02 fim do N+1'],
  ['03-pool-conexoes', '03 pool'],
  ['04-indice-email', '04 índice e-mail'],
  ['05-indice-status', '05 índice status'],
  ['06-indice-data', '06 índice data'],
  ['07-view-top-produtos', '07 view top-produtos'],
  ['09-log-sem-corpo', '09 log sem corpo'],
];

function lerMetricas(rotulo) {
  const arquivo = path.join('analise', 'saidas', `${rotulo}-medianas.md`);
  const texto = fs.readFileSync(arquivo, 'utf8');
  const metricas = {};
  for (const linha of texto.split('\n')) {
    const m = linha.match(/^\| (req_s|p95_ms) \| ([\d.]+) \| ([\d.]+) \|/);
    if (m) metricas[m[1]] = { antes: Number(m[2]), depois: Number(m[3]) };
  }
  if (!metricas.req_s || !metricas.p95_ms) throw new Error(`métricas não encontradas em ${arquivo}`);
  return metricas;
}

const pontos = [];
const primeiro = lerMetricas(EXPERIMENTOS[0][0]);
pontos.push({ nome: '00 linha de base', req_s: primeiro.req_s.antes, p95_ms: primeiro.p95_ms.antes });
for (const [rotulo, nome] of EXPERIMENTOS) {
  const m = lerMetricas(rotulo);
  pontos.push({ nome, req_s: m.req_s.depois, p95_ms: m.p95_ms.depois });
}

const fmt = (n, casas) => n.toLocaleString('pt-BR', { minimumFractionDigits: casas, maximumFractionDigits: casas });
const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');

// Barras horizontais: os nomes das etapas ficam legíveis à esquerda.
const LARG_PAINEL = 430;
const ROTULO = 150;
const ALT_BARRA = 22;
const PASSO = 32;
const TOPO = 78;
const ALTURA = TOPO + pontos.length * PASSO + 40;
const LARGURA = LARG_PAINEL * 2 + 40;

function painel(x0, titulo, subtitulo, campo, formatar) {
  const max = Math.max(...pontos.map((p) => p[campo]));
  const largMax = LARG_PAINEL - ROTULO - 70;
  let s = `<g transform="translate(${x0},0)">`;
  s += `<text class="titulo" x="0" y="30">${esc(titulo)}</text>`;
  s += `<text class="sub" x="0" y="50">${esc(subtitulo)}</text>`;
  s += `<line class="eixo" x1="${ROTULO}" y1="${TOPO - 8}" x2="${ROTULO}" y2="${TOPO + pontos.length * PASSO - 6}"/>`;
  pontos.forEach((p, i) => {
    const y = TOPO + i * PASSO;
    const w = Math.max(2, (p[campo] / max) * largMax);
    s += `<text class="rotulo" x="${ROTULO - 8}" y="${y + ALT_BARRA / 2 + 4}" text-anchor="end">${esc(p.nome)}</text>`;
    // Ponta arredondada de 4 px só no fim da barra; a base fica reta no eixo.
    s += `<path class="barra" d="M${ROTULO},${y} h${Math.max(0, w - 4)} a4,4 0 0 1 4,4 v${ALT_BARRA - 8} a4,4 0 0 1 -4,4 h${-Math.max(0, w - 4)} z"><title>${esc(p.nome)}: ${formatar(p[campo])}</title></path>`;
    s += `<text class="valor" x="${ROTULO + w + 6}" y="${y + ALT_BARRA / 2 + 4}">${formatar(p[campo])}</text>`;
  });
  s += '</g>';
  return s;
}

const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${LARGURA}" height="${ALTURA}" viewBox="0 0 ${LARGURA} ${ALTURA}" role="img" aria-labelledby="t d">
<title id="t">Evolução da vazão e do p95 a cada experimento</title>
<desc id="d">Mediana de 3 execuções do scripts/medir.sh (20 usuários virtuais, 60 s, semente 42). ${pontos.map((p) => `${p.nome}: ${fmt(p.req_s, 2)} req/s, p95 ${fmt(p.p95_ms, 0)} ms`).join('; ')}.</desc>
<style>
  svg { --fundo: #fcfcfb; --texto: #0b0b0b; --texto-2: #52514e; --eixo: #c3c2b7; --serie: #2a78d6; }
  @media (prefers-color-scheme: dark) {
    svg { --fundo: #1a1a19; --texto: #f0efec; --texto-2: #c3c2b7; --eixo: #52514e; --serie: #3987e5; }
  }
  text { font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; fill: var(--texto); }
  .titulo { font-size: 16px; font-weight: 600; }
  .sub, .rodape { font-size: 12px; fill: var(--texto-2); }
  .rotulo { font-size: 12px; fill: var(--texto-2); }
  .valor { font-size: 12px; font-variant-numeric: tabular-nums; }
  .barra { fill: var(--serie); }
  .eixo { stroke: var(--eixo); stroke-width: 1; }
</style>
<rect width="100%" height="100%" fill="var(--fundo)"/>
${painel(16, 'Requisições por segundo', 'maior é melhor', 'req_s', (v) => fmt(v, 2))}
${painel(16 + LARG_PAINEL + 8, 'p95 geral (ms)', 'menor é melhor', 'p95_ms', (v) => fmt(v, 0))}
<text class="rodape" x="16" y="${ALTURA - 14}">Mediana de 3 execuções do scripts/medir.sh. Fonte: analise/saidas/*-medianas.md, gerado por analise/grafico-evolucao.js.</text>
</svg>
`;

fs.mkdirSync(path.join('artigo', 'img'), { recursive: true });
fs.writeFileSync(path.join('artigo', 'img', 'evolucao.svg'), svg);
console.log('gravado artigo/img/evolucao.svg');
for (const p of pontos) console.log(`${p.nome}\t${p.req_s}\t${p.p95_ms}`);
