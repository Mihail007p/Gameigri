#!/usr/bin/env node
/**
 * Gameigri — автотесты игровой логики без браузера.
 *
 * Запуск:  node tools/test_game.js
 * Зачем:   проверяет физику, столкновения, паузу, рекорды, утечки и баланс сложности
 *          прямо из index.html — без установки браузера и внешних зависимостей.
 *
 * Как это работает: скрипт вытаскивает <script> из index.html, подменяет DOM и canvas
 * заглушками и прокручивает кадры вручную (детерминированно, 60 fps).
 */
'use strict';
const fs = require('fs');
const path = require('path');

const HTML = path.join(__dirname, '..', 'index.html');
const js = /<script>([\s\S]*)<\/script>/.exec(fs.readFileSync(HTML, 'utf8'))[1];

/* ---------- стенд: DOM + canvas заглушки ---------- */
const listeners = {};
const gradient = { addColorStop() {} };
const ctx = new Proxy({}, {
  get: (t, p) => p === 'createLinearGradient' ? (() => gradient) : (p in t ? t[p] : (() => {})),
  set: (t, p, v) => (t[p] = v, true)
});
const mkEl = id => ({
  id, style: {}, dataset: { k: 'gas' }, textContent: '',
  classList: { toggle() {}, add() {} },
  addEventListener() {}, getContext: () => ctx
});
global.document = { getElementById: mkEl, querySelectorAll: () => [], addEventListener() {}, body: { classList: { add() {} } } };
global.window = global;
global.addEventListener = (t, fn) => ((listeners[t] = listeners[t] || []).push(fn));
global.matchMedia = () => ({ matches: false });
global.clock = 1000;
global.performance = { now: () => global.clock };
global.CanvasRenderingContext2D = function () {};
global.CanvasRenderingContext2D.prototype = {};
global.localStorage = { _d: {}, getItem(k) { return k in this._d ? this._d[k] : null; }, setItem(k, v) { this._d[k] = v; } };
let rafCb = null;
global.requestAnimationFrame = cb => (rafCb = cb);
global.setTimeout = () => {};

eval(js);
const { Game, CFG, Road } = global.Gameigri;

/* ---------- мини-фреймворк проверок ---------- */
let failed = 0;
const ok = (cond, msg, extra = '') => {
  if (!cond) failed++;
  console.log(`  ${cond ? '✓' : '✗'} ${msg}${extra ? ' — ' + extra : ''}`);
};
const group = t => console.log(`\n${t}`);
const key = (t, k) => (listeners[t] || []).forEach(f => f({ key: k, preventDefault() {} }));

const DT = 1000 / 60;
let now = global.clock;
const step = () => { global.clock = now += DT; rafCb(now); };
// шаг по «чистой» дороге: убираем трафик, чтобы проверять механику без случайных аварий
const stepClean = () => { Game.cars.length = 0; step(); };

/* ---------- 1. Загрузка и старт ---------- */
group('1. Загрузка и разгон');
ok(true, 'index.html разобран, скрипт выполнился без исключений');
Game.init();
Game.start();
ok(Game.state === 'play', 'состояние после старта — play');

const startMeters = Game.meters, startSpeed = Game.player.speed;
for (let i = 0; i < 180; i++) { key('keydown', 'ArrowUp'); stepClean(); }
ok(Game.meters > startMeters, 'дистанция растёт со временем', `${startMeters} → ${Game.meters} м`);
ok(Game.player.speed > startSpeed, 'газ увеличивает скорость', `${Math.round(startSpeed)} → ${Math.round(Game.player.speed)} px/с`);

/* ---------- 2. Руль ---------- */
group('2. Руль и границы дороги');
const LB = Road.left() + Game.player.w / 2, RB = Road.right() - Game.player.w / 2;
key('keydown', 'ArrowLeft');
for (let i = 0; i < 240; i++) stepClean();
key('keyup', 'ArrowLeft');
const leftX = Game.player.x;
ok(Math.abs(leftX - LB) < 1, 'игрок упирается в левую обочину и не уходит за неё', `x=${leftX.toFixed(1)} при границе ${LB.toFixed(1)}`);
key('keydown', 'ArrowRight');
for (let i = 0; i < 480; i++) stepClean();
key('keyup', 'ArrowRight');
const rightX = Game.player.x;
ok(Math.abs(rightX - RB) < 1, 'игрок упирается в правую обочину и не уходит за неё', `x=${rightX.toFixed(1)} при границе ${RB.toFixed(1)}`);
ok(Game.state === 'play' || Game.state === 'over', 'состояние игры остаётся корректным', Game.state);

/* ---------- 3. Трафик и утечки ---------- */
group('3. Трафик');
Game.start();
let maxCars = 0;
for (let i = 0; i < 600; i++) { step(); maxCars = Math.max(maxCars, Game.cars.length); }
ok(Game.cars.length > 0, 'машины появляются на дороге', `сейчас ${Game.cars.length}`);
ok(maxCars < 25, 'количество машин ограничено (нет утечки)', `максимум ${maxCars}`);
// держим тормоз: весь трафик обгоняет игрока — раньше такие машины зависали за кадром навсегда
for (let i = 0; i < 900; i++) { key('keydown', 'ArrowDown'); step(); }
ok(Game.cars.length < 15, 'машины, ушедшие вверх за экран, удаляются', `осталось ${Game.cars.length}`);
key('keyup', 'ArrowDown');

/* ---------- 4. Столкновения и рестарт ---------- */
group('4. Столкновения и рестарт');
let crashes = 0, restarts = 0, firstCrash = null;
for (let i = 0; i < 12000 && crashes < 5; i++) {
  if (Game.state === 'over') {
    crashes++;
    if (firstCrash === null) firstCrash = Game.meters;
    Game.start(); restarts++;
  }
  if (i % 9 === 0) { const k = Math.random() < .5 ? 'ArrowLeft' : 'ArrowRight'; key('keyup', k === 'ArrowLeft' ? 'ArrowRight' : 'ArrowLeft'); key('keydown', k); }
  key('keydown', 'ArrowUp');
  step();
}
ok(crashes > 0, 'столкновение с трафиком завершает заезд', `аварий: ${crashes}`);
ok(restarts === crashes, 'рестарт возвращает в игру', `рестартов: ${restarts}`);
ok(Game.meters >= 0 && Game.meters < 1e6, 'после рестарта счёт корректный', `${Game.meters} м`);

/* ---------- 5. Пауза ---------- */
group('5. Пауза');
Game.start();
for (let i = 0; i < 120; i++) stepClean();
Game.togglePause();
const p1 = Game.meters;
for (let i = 0; i < 180; i++) stepClean();
ok(Game.meters === p1, 'на паузе дистанция не меняется', `${p1} м`);
Game.togglePause();
for (let i = 0; i < 60; i++) stepClean();
ok(Game.meters > p1, 'после снятия паузы игра продолжается', `${Game.meters} м`);

/* ---------- 6. Рекорд ---------- */
group('6. Рекорд');
const saved = Number(localStorage.getItem(CFG.bestKey));
ok(saved > 0, 'рекорд сохраняется в localStorage', `${saved} м`);

/* ---------- 7. Баланс сложности ---------- */
group('7. Баланс: расчётливый бот (оценивает время до столкновения)');
const held = { ArrowLeft: false, ArrowRight: false, ArrowUp: false };
const hold = (k, on) => { if (held[k] === on) return; held[k] = on; key(on ? 'keydown' : 'keyup', k); };
Game.start();
const runs = [];
for (let i = 0; i < 600 * 60; i++) {
  const p = Game.player;
  const danger = new Array(CFG.lanes).fill(0);
  for (let L = 0; L < CFG.lanes; L++) {
    const cx = Road.laneCenter(L);
    for (const c of Game.cars) {
      if (Math.abs(c.x - cx) > (c.w + p.w) / 2 + 4) continue;
      if (c.y > p.y + p.h) continue;
      const rel = p.speed - c.speed;
      if (rel <= 1) { danger[L] += 0.02; continue; }
      const gap = p.y - c.y - (p.h + c.h) / 2;
      danger[L] += 1 / (Math.pow(Math.max(gap, 0) / rel, 2) + 0.05);
    }
    danger[L] += Math.abs(cx - p.x) / 400;
  }
  let best = 0; for (let L = 1; L < danger.length; L++) if (danger[L] < danger[best]) best = L;
  const tx = Road.laneCenter(best);
  hold('ArrowLeft', p.x > tx + 4);
  hold('ArrowRight', p.x < tx - 4);
  hold('ArrowUp', danger[best] < 3);
  step();
  if (Game.state === 'over') { runs.push(Game.meters); Game.start(); }
}
runs.push(Game.meters);
const avg = runs.reduce((a, b) => a + b, 0) / runs.length;
ok(avg > 700, 'игра проходима: бот уезжает далеко', `средний заезд ${avg.toFixed(0)} м, лучший ${Math.max(...runs)} м`);

/* ---------- итог ---------- */
console.log(`\n${failed === 0 ? '✅ ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ' : `❌ ПРОВАЛЕНО ПРОВЕРОК: ${failed}`}`);
process.exit(failed === 0 ? 0 : 1);
