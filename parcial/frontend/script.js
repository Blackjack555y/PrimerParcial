document.addEventListener('DOMContentLoaded', () => {
  const zones = document.querySelectorAll('.zone');
  zones.forEach((zone) => {
    zone.setAttribute('tabindex', '0');
    zone.setAttribute('role', 'button');
    const selectZone = () => {
      zones.forEach((item) => item.classList.remove('is-selected'));
      zone.classList.add('is-selected');
    };
    zone.addEventListener('click', selectZone);
    zone.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        selectZone();
      }
    });
  });

  new PlanPlayer().init();
});

// Zone centers mirror the hardcoded <g transform="translate(x y)"> values in
// index.html. This visualizer is built for this specific 5-zone map, not a
// generic renderer -- see design.md/CONTINUACION.md: the graph stays static,
// only a playback layer is added on top of it.
const ZONE_POS = {
  Z1: [220, 150],
  Z2: [540, 150],
  Z3: [540, 420],
  Z4: [220, 420],
  Z5: [220, 680]
};

const DOOR_LINE_ID = {
  DOOR1: 'corridor-door1',
  DOOR2: 'corridor-door2',
  DOOR3: 'corridor-door3'
};

const STATION_MARKER_ID = {
  GENERATOR: 'station-GENERATOR',
  COMMAND: 'station-COMMAND',
  ARTILLERY: 'station-ARTILLERY'
};

const KEY_MARKER_ID = {
  KEY1: 'marker-KEY1',
  KEY2: 'marker-KEY2',
  KEY3: 'marker-KEY3'
};

class PlanPlayer {
  constructor() {
    this.scenario = null;
    this.steps = [];
    this.totalCost = 0;
    this.currentIndex = 0; // 0 = estado inicial, N = despues del paso N
    this.timer = null;

    this.el = {
      solveBtn: document.getElementById('btn-solve'),
      solveStatus: document.getElementById('solve-status'),
      resetBtn: document.getElementById('btn-reset'),
      prevBtn: document.getElementById('btn-prev'),
      playBtn: document.getElementById('btn-play'),
      nextBtn: document.getElementById('btn-next'),
      robot: document.getElementById('robot-marker'),
      batteryFill: document.getElementById('battery-fill'),
      batteryValue: document.getElementById('battery-value'),
      costFill: document.getElementById('cost-fill'),
      costValue: document.getElementById('cost-value'),
      stepIndex: document.getElementById('step-index'),
      stepTotal: document.getElementById('step-total'),
      actionText: document.getElementById('action-text'),
      payloadList: document.getElementById('payload-list'),
      stepLog: document.getElementById('step-log'),
      summary: document.getElementById('summary'),
      summaryBody: document.getElementById('summary-body'),
      summaryBadge: document.getElementById('summary-badge')
    };
  }

  init() {
    this.el.solveBtn.addEventListener('click', () => this.solve());
    this.el.resetBtn.addEventListener('click', () => this.goTo(0));
    this.el.prevBtn.addEventListener('click', () => this.goTo(this.currentIndex - 1));
    this.el.nextBtn.addEventListener('click', () => this.goTo(this.currentIndex + 1));
    this.el.playBtn.addEventListener('click', () => this.togglePlay());
  }

  async solve() {
    this.stopPlay();
    this.el.solveBtn.disabled = true;
    this.el.solveStatus.textContent = 'Resolviendo...';

    try {
      const scenarioResponse = await fetch('/api/scenario');
      if (!scenarioResponse.ok) throw new Error(`GET /api/scenario -> ${scenarioResponse.status}`);
      this.scenario = await scenarioResponse.json();

      const solveResponse = await fetch('/api/solve', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(this.scenario)
      });
      if (!solveResponse.ok) throw new Error(`POST /api/solve -> ${solveResponse.status}`);
      const result = await solveResponse.json();

      if (!result.solution_found) {
        this.el.solveStatus.textContent = `Sin solucion: ${result.message || 'FAILURE'}`;
        this.showFailureSummary(result.message);
        this.el.solveBtn.disabled = false;
        return;
      }

      this.steps = result.steps;
      this.totalCost = result.total_cost;
      this.el.solveStatus.textContent = `Costo ${result.total_cost} - ${this.steps.length} pasos`;
      this.el.stepTotal.textContent = this.steps.length;
      this.buildLog();
      this.buildSummary();
      [this.el.resetBtn, this.el.prevBtn, this.el.playBtn, this.el.nextBtn].forEach((btn) => { btn.disabled = false; });
      this.goTo(0);
    } catch (error) {
      this.el.solveStatus.textContent = `Error: ${error.message}. Corre "ruby server.rb" primero.`;
    } finally {
      this.el.solveBtn.disabled = false;
    }
  }

  buildLog() {
    this.el.stepLog.innerHTML = '';
    this.steps.forEach((step, index) => {
      const li = document.createElement('li');
      li.textContent = this.describe(step);
      li.dataset.index = String(index + 1);
      li.addEventListener('click', () => this.goTo(index + 1));
      this.el.stepLog.appendChild(li);
    });
  }

  describe(step) {
    switch (step.op) {
      case 'MOVE': return `MOVE ${step.from || '?'} -> ${step.to} (costo ${step.cost})`;
      case 'PICKUP': return `PICKUP ${step.item} (costo ${step.cost})`;
      case 'DROP': return `DROP ${step.item} (costo ${step.cost})`;
      case 'INTERACT': {
        const extra = step.action === 'REPAIR' ? ` [consume ${step.consumes}]` : '';
        return `INTERACT ${step.action} ${step.target}${extra} (costo ${step.cost})`;
      }
      default: return JSON.stringify(step);
    }
  }

  // Full-sentence version for the end-of-page summary table, as opposed to
  // the compact log line from describe().
  describeNatural(step) {
    switch (step.op) {
      case 'MOVE': return `Se mueve de ${step.from || '?'} a ${step.to}.`;
      case 'PICKUP': return `Recoge ${step.item} del suelo.`;
      case 'DROP': return `Deja ${step.item} en el suelo.`;
      case 'INTERACT':
        switch (step.action) {
          case 'OPEN_DOOR': return `Abre la puerta ${step.target}.`;
          case 'REPAIR': return `Repara ${step.target} usando ${step.consumes}.`;
          case 'ACTIVATE': return `Activa la estacion ${step.target}.`;
          case 'RECHARGE': return `Recarga la bateria al maximo en ${step.target}.`;
          default: return `${step.action} sobre ${step.target}.`;
        }
      default: return JSON.stringify(step);
    }
  }

  opChip(step) {
    const kind = step.op.toLowerCase();
    const label = step.op === 'INTERACT' ? step.action : step.op;
    return `<span class="op-chip op-${kind}">${label}</span>`;
  }

  showFailureSummary(message) {
    this.el.summary.hidden = false;
    this.el.summaryBadge.textContent = 'SIN SOLUCION';
    this.el.summaryBadge.style.background = 'var(--red)';
    this.el.summaryBody.innerHTML = `<tr><td colspan="6">${message || 'La mision no se puede completar (FAILURE).'}</td></tr>`;
  }

  // Walks every step once, accumulating cost/battery/payload, to render the
  // full plan as a natural-language table -- independent of playback, so it
  // is visible right after solving without pressing play.
  buildSummary() {
    const batteryMax = this.scenario.robot.battery_max;
    let battery = this.scenario.robot.battery_start;
    let cost = 0;
    const payload = [];

    const rows = this.steps.map((step, index) => {
      cost += step.cost;
      battery -= step.cost;
      if (step.op === 'INTERACT' && step.action === 'RECHARGE') battery = batteryMax;
      if (step.op === 'PICKUP') payload.push(step.item);
      if (step.op === 'DROP') this.removeOne(payload, step.item);
      if (step.op === 'INTERACT' && step.action === 'REPAIR') this.removeOne(payload, step.consumes);

      return `<tr>
        <td class="col-index">${index + 1}</td>
        <td class="col-action">${this.opChip(step)}${this.describeNatural(step)}</td>
        <td class="col-cost">${step.cost}</td>
        <td class="col-total">${cost} / ${this.totalCost}</td>
        <td class="col-battery">${battery} / ${batteryMax}</td>
        <td class="col-payload">${payload.length ? payload.join(', ') : '—'}</td>
      </tr>`;
    });

    this.el.summary.hidden = false;
    this.el.summaryBadge.textContent = `MISION COMPLETA · Costo total ${this.totalCost}`;
    this.el.summaryBadge.style.background = '#2f8f4e';
    this.el.summaryBody.innerHTML = rows.join('');
  }

  togglePlay() {
    if (this.timer) {
      this.stopPlay();
      return;
    }
    if (this.currentIndex >= this.steps.length) this.goTo(0);
    this.el.playBtn.textContent = String.fromCharCode(0x23f8); // pause icon
    this.timer = setInterval(() => {
      if (this.currentIndex >= this.steps.length) {
        this.stopPlay();
        return;
      }
      this.goTo(this.currentIndex + 1);
    }, 850);
  }

  stopPlay() {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
    this.el.playBtn.textContent = String.fromCharCode(0x25b6); // play icon
  }

  goTo(index) {
    const clamped = Math.max(0, Math.min(index, this.steps.length));
    this.currentIndex = clamped;
    this.render();
  }

  // Recomputes world state by replaying steps[0..currentIndex) from the
  // scenario's initial conditions. Simpler and less error-prone than
  // incremental undo, and cheap at this plan size.
  buildWorld() {
    const robot = this.scenario.robot;
    const world = {
      pos: robot.start,
      battery: robot.battery_start,
      payload: [],
      doorsOpen: new Set((this.scenario.doors || []).filter((d) => d.state === 'OPEN').map((d) => d.id)),
      stationsOnline: new Set((this.scenario.stations || []).filter((s) => s.state === 'ONLINE').map((s) => s.id)),
      everCollected: new Set(),
      costSoFar: 0
    };

    for (let i = 0; i < this.currentIndex; i += 1) {
      this.applyStep(world, this.steps[i]);
    }
    return world;
  }

  applyStep(world, step) {
    world.costSoFar += step.cost;
    world.battery -= step.cost;
    switch (step.op) {
      case 'MOVE':
        world.pos = step.to;
        break;
      case 'PICKUP':
        world.payload.push(step.item);
        world.everCollected.add(step.item);
        break;
      case 'DROP':
        this.removeOne(world.payload, step.item);
        break;
      case 'INTERACT':
        if (step.action === 'OPEN_DOOR') world.doorsOpen.add(step.target);
        else if (step.action === 'REPAIR') this.removeOne(world.payload, step.consumes);
        else if (step.action === 'ACTIVATE') world.stationsOnline.add(step.target);
        else if (step.action === 'RECHARGE') world.battery = this.scenario.robot.battery_max;
        break;
      default:
        break;
    }
  }

  removeOne(list, item) {
    const idx = list.indexOf(item);
    if (idx !== -1) list.splice(idx, 1);
  }

  render() {
    const world = this.buildWorld();
    const batteryMax = this.scenario.robot.battery_max;

    const [x, y] = ZONE_POS[world.pos] || [220, 150];
    this.el.robot.setAttribute('cx', String(x));
    this.el.robot.setAttribute('cy', String(y));

    this.el.batteryValue.textContent = `${world.battery} / ${batteryMax}`;
    this.el.batteryFill.style.width = `${Math.max(0, (world.battery / batteryMax) * 100)}%`;

    this.el.costValue.textContent = `${world.costSoFar} / ${this.totalCost}`;
    this.el.costFill.style.width = this.totalCost ? `${(world.costSoFar / this.totalCost) * 100}%` : '0%';

    this.el.stepIndex.textContent = String(this.currentIndex);
    this.el.actionText.textContent = this.currentIndex === 0
      ? 'Estado inicial.'
      : this.currentIndex >= this.steps.length
        ? 'Plan completo: todas las estaciones online.'
        : this.describe(this.steps[this.currentIndex - 1]);

    this.el.payloadList.innerHTML = '';
    world.payload.forEach((item) => {
      const li = document.createElement('li');
      li.textContent = item;
      this.el.payloadList.appendChild(li);
    });

    Object.entries(DOOR_LINE_ID).forEach(([doorId, lineId]) => {
      const line = document.getElementById(lineId);
      if (line) line.classList.toggle('door-open', world.doorsOpen.has(doorId));
    });

    Object.entries(STATION_MARKER_ID).forEach(([stationId, markerId]) => {
      const marker = document.getElementById(markerId);
      if (marker) marker.classList.toggle('online', world.stationsOnline.has(stationId));
    });

    Object.entries(KEY_MARKER_ID).forEach(([keyId, markerId]) => {
      const marker = document.getElementById(markerId);
      if (marker) marker.classList.toggle('collected', world.everCollected.has(keyId));
    });

    Array.from(this.el.stepLog.children).forEach((li, i) => {
      li.classList.toggle('is-current', i + 1 === this.currentIndex);
      li.classList.toggle('is-done', i + 1 < this.currentIndex);
    });

    if (this.currentIndex >= this.steps.length) this.stopPlay();
  }
}
