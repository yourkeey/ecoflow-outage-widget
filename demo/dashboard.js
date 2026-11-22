"use strict";

const sim = RiverSimulation;
const element = (id) => document.getElementById(id);
const write = (id, text) => { element(id).textContent = text; };
const chart = element("history-chart");
const spark = element("load-spark");
const historyMinutes = 45;
const mint = "#72e3bc";
const blue = "#a3c5f4";
const dateLabels = { today: "Сегодня", tomorrow: "Завтра", latest: "Последний график" };
let state = sim.createSimulation();
let paused = false;
let chartMode = "power";
let scheduleDay = "today";
let selectedSample = null;

function duration(minutes) {
  return sim.duration(minutes).replace("h", " ч").replace("m", " мин");
}

function timeRange([start, end]) {
  return sim.clock(start) + " — " + sim.clock(end);
}

function updateTrack(name, value) {
  const progress = element(name + "-progress");
  progress.setAttribute("aria-valuenow", String(Math.round(value)));
  progress.dataset.tone = value < 20 ? "warning" : "normal";
  element(name + "-fill").style.width = value + "%";
}

function render() {
  const live = sim.telemetry(state);
  const day = Math.floor(state.minute / sim.minutesPerDay);
  const time = state.minute % sim.minutesPerDay;
  write("clock", "Демо · " + sim.clock(time) + " · день " + (day + 1) +
    (paused ? " · пауза" : " · 1 мин/сек"));

  const percent = state.energy / sim.capacity * 100;
  write("charge", Math.round(percent) + " %");
  write("battery-energy", Math.round(state.energy) + " / " + sim.capacity + " Вт·ч");
  updateTrack("battery", percent);
  const powerStatus = live.onGrid ? "питание от сети" : live.online ? "питание от батареи" : "батарея разряжена";
  const status = element("power-status");
  const statusText = "Демонстрация · " + powerStatus;
  if (status.textContent !== statusText) status.textContent = statusText;
  status.dataset.tone = live.online ? "normal" : "critical";
  write("input-watts", live.input + " Вт");
  write("output-watts", live.output + " Вт");
  const estimate = live.onGrid
    ? (live.timeToFull ? "До полного заряда: " + duration(live.timeToFull) : "Батарея заряжена")
    : "Время работы: " + duration(live.runtime ?? 0);
  write("estimate", estimate);

  for (const device of ["cpu", "gpu"]) {
    write(device + "-temp", live.online ? live[device] + " °C" : "Офлайн");
    write(device + "-load", live.online ? "Загрузка " + live[device + "Load"] + "%" : "");
  }
  for (const name of ["session", "weekly"]) {
    const budget = state[name];
    write(name + "-value", "Осталось " + Math.round(budget.left) + "%");
    write(name + "-reset", "Сброс через " + duration(budget.reset - state.minute));
    updateTrack(name, budget.left);
  }
  renderSchedule(day, time);
  drawCharts();
}

function renderTimeline(timeline, day, currentTime) {
  if (timeline.dataset.day !== String(day)) {
    timeline.dataset.day = String(day);
    const blocks = sim.windows(day).map(([start, end]) => {
      const slot = document.createElement("span");
      slot.className = "outage-slot";
      slot.title = timeRange([start, end]);
      slot.dataset.end = String(end);
      slot.style.left = start / sim.minutesPerDay * 100 + "%";
      slot.style.width = (end - start) / sim.minutesPerDay * 100 + "%";
      return slot;
    });
    const marker = document.createElement("span");
    marker.className = "time-marker";
    timeline.replaceChildren(...blocks, marker);
  }

  const marker = timeline.querySelector(".time-marker");
  marker.hidden = currentTime === null;
  marker.style.left = (currentTime ?? 0) / sim.minutesPerDay * 100 + "%";
  for (const slot of timeline.querySelectorAll(".outage-slot")) {
    slot.classList.toggle("past", currentTime !== null && Number(slot.dataset.end) <= currentTime);
  }
}

function renderSchedule(day, time) {
  const event = sim.scheduleAt(state.minute);
  const eventWindows = sim.windows(day + Number(event.tomorrow));
  const upcoming = eventWindows.find(([start, end]) => event.active ? end === event.time : start === event.time);
  write("outage-label", event.active ? "До включения по графику" : "До отключения по графику");
  write("outage-countdown", sim.clock(event.minutes) + ":00");
  write("outage-hint", (event.tomorrow ? "Завтра" : "Сегодня") + " · " + timeRange(upcoming) + " · черга 2.2");
  renderTimeline(element("station-timeline"), day, time);

  const selectedDay = day + Number(scheduleDay !== "today");
  const dayWindows = sim.windows(selectedDay);
  const highlighted = scheduleDay === "today" ? dayWindows.find(([, end]) => end > time) ?? dayWindows[0] : dayWindows[0];
  const total = dayWindows.reduce((minutes, [start, end]) => minutes + end - start, 0);
  write("schedule-day", dateLabels[scheduleDay]);
  write("schedule-interval", timeRange(highlighted));
  write("schedule-summary", "Всего: " + duration(total) + " · интервалов " + dayWindows.length);
  renderTimeline(element("schedule-timeline"), selectedDay, selectedDay === day ? time : null);
  const list = element("outage-windows");
  if (list.dataset.day !== String(selectedDay)) {
    list.dataset.day = String(selectedDay);
    list.replaceChildren(...dayWindows.map(([start, end]) => {
      const item = document.createElement("li");
      const range = document.createElement("strong");
      const length = document.createElement("span");
      range.textContent = timeRange([start, end]);
      length.textContent = duration(end - start);
      item.append(range, length);
      return item;
    }));
  }
}

function getPlot(canvas) {
  const { width, height } = canvas.getBoundingClientRect();
  if (!width || !height) return null;
  const dpr = window.devicePixelRatio || 1;
  const pixelWidth = Math.round(width * dpr);
  const pixelHeight = Math.round(height * dpr);
  if (canvas.width !== pixelWidth || canvas.height !== pixelHeight) {
    canvas.width = pixelWidth;
    canvas.height = pixelHeight;
  }
  const context = canvas.getContext("2d");
  if (!context) return null;
  context.setTransform(dpr, 0, 0, dpr, 0, 0);
  context.clearRect(0, 0, width, height);
  return { width, height, context };
}

function line(context, samples, key, x, y, color, width) {
  context.beginPath();
  let connected = false;
  samples.forEach((sample, index) => {
    const value = sample[key];
    if (value === null) {
      connected = false;
    } else {
      if (connected) context.lineTo(x(index), y(value));
      else context.moveTo(x(index), y(value));
      connected = true;
    }
  });
  context.strokeStyle = color;
  context.lineWidth = width;
  context.lineJoin = "round";
  context.stroke();
}

function drawSpark(samples) {
  const plot = getPlot(spark);
  if (!plot) return;
  const { width, height, context } = plot;
  const last = samples.length - 1;
  const max = Math.max(50, Math.ceil(Math.max(...samples.map((sample) => sample.output)) / 50) * 50);
  const x = (index) => 2 + (width - 5) * index / last;
  // Leave a little space above the data line for the most recent marker.
  const y = (value) => height - 2 - (height - 6) * value / max;
  context.fillStyle = "#b3c5d788";
  context.fillRect(2, height - 1, width - 5, 1);
  line(context, samples, "output", x, y, mint, 1.4);
  context.beginPath();
  context.arc(x(last), y(samples[last].output), 2, 0, Math.PI * 2);
  context.fillStyle = "#abefd7";
  context.fill();
}

function drawHistory(samples) {
  const plot = getPlot(chart);
  if (!plot) return;
  const { width, height, context } = plot;
  const left = 24;
  const right = width - 12;
  const top = 8;
  const bottom = height - 18;
  const temperature = chartMode === "temperature";
  const ticks = temperature ? [30, 50, 70, 90] : [0, 100, 200, 300];
  const x = (index) => left + (right - left) * index / historyMinutes;
  const y = (value) => bottom - (bottom - top) * (value - ticks[0]) / (ticks.at(-1) - ticks[0]);

  context.font = "10px Segoe UI, sans-serif";
  context.fillStyle = "#bdcbe2";
  for (const tick of ticks) {
    context.strokeStyle = "#8193ba70";
    context.lineWidth = 1;
    context.beginPath();
    context.moveTo(left, y(tick));
    context.lineTo(right, y(tick));
    context.stroke();
    context.fillText(String(tick), 2, y(tick) + 3);
  }
  for (const index of [0, 15, 30, historyMinutes]) {
    const label = sim.clock(samples[index].minute % sim.minutesPerDay);
    const labelWidth = context.measureText(label).width;
    context.fillText(label, Math.min(x(index) - labelWidth / 2, width - labelWidth), height - 3);
  }

  if (temperature) {
    line(context, samples, "cpu", x, y, mint, 1.6);
    line(context, samples, "gpu", x, y, blue, 1.6);
  } else {
    line(context, samples, "output", x, y, mint, 1.6);
  }
  if (selectedSample === null) {
    write("chart-value", "Наведите на график или используйте стрелки.");
    return;
  }

  const sample = samples[selectedSample];
  context.fillStyle = "#edf4f8";
  context.fillRect(x(selectedSample), top, 1, bottom - top);
  const reading = temperature
    ? (sample.online ? "CPU " + sample.cpu + " °C · GPU " + sample.gpu + " °C" : "ПК выключен")
    : "Выход " + sample.output + " Вт";
  write("chart-value", sim.clock(sample.minute % sim.minutesPerDay) + " · " + reading);
}

function drawCharts() {
  const samples = state.history.slice(-historyMinutes - 1);
  drawSpark(samples);
  drawHistory(samples);
}

function bindSegments(id, update) {
  const group = element(id);
  for (const button of group.querySelectorAll("button")) {
    button.addEventListener("click", () => {
      selectSegment(group, button.dataset.value);
      update(button.dataset.value);
      render();
    });
  }
}

function selectSegment(group, value) {
  for (const button of group.querySelectorAll("button")) {
    button.setAttribute("aria-pressed", String(button.dataset.value === value));
  }
}

function showPanel(name) {
  element("station").hidden = name !== "station";
  element("schedule").hidden = name !== "schedule";
  selectSegment(element("main-tabs"), name);
}

function setWidgetVisible(visible) {
  element("widget").hidden = !visible;
  element("restore-widget").hidden = visible;
  element(visible ? "hide-widget" : "restore-widget").focus();
}

function replaceCurrentSample() {
  state.history[state.history.length - 1] = sim.telemetry(state);
}

bindSegments("main-tabs", showPanel);
bindSegments("grid-controls", (value) => { state.power = value; replaceCurrentSample(); });
bindSegments("workload-controls", (value) => { state.workload = value; replaceCurrentSample(); });
bindSegments("schedule-controls", (value) => { scheduleDay = value; });
bindSegments("chart-controls", (value) => {
  chartMode = value;
  const labels = value === "temperature" ? ["CPU · °C", "GPU · °C"] : ["Выход · Вт"];
  element("chart-legend").replaceChildren(...labels.map((label) => {
    const item = document.createElement("span");
    item.textContent = label;
    return item;
  }));
});

element("open-schedule").addEventListener("click", () => {
  showPanel("schedule");
  element("main-tabs").querySelector('[data-value="schedule"]').focus();
  render();
});
element("open-history").addEventListener("click", () => {
  element("station-details").open = true;
  chart.focus();
  drawCharts();
});
element("hide-widget").addEventListener("click", () => setWidgetVisible(false));
element("restore-widget").addEventListener("click", () => setWidgetVisible(true));
element("open-settings").addEventListener("click", () => element("settings").showModal());
element("close-settings").addEventListener("click", () => element("settings").close());

element("pause").addEventListener("click", () => {
  paused = !paused;
  element("pause").setAttribute("aria-pressed", String(paused));
  write("pause", paused ? "Продолжить" : "Пауза");
  write("speed-label", paused ? "Время · пауза" : "Время · 1 мин/сек");
  render();
});

function step(minutes) {
  sim.advance(state, minutes);
  render();
}

for (const button of document.querySelectorAll(".refresh")) {
  button.addEventListener("click", () => step(1));
}
element("step").addEventListener("click", () => step(15));
element("reset").addEventListener("click", () => {
  state = sim.createSimulation();
  selectedSample = null;
  selectSegment(element("grid-controls"), state.power);
  selectSegment(element("workload-controls"), state.workload);
  render();
});

chart.addEventListener("pointermove", (event) => {
  const bounds = chart.getBoundingClientRect();
  const fraction = (event.clientX - bounds.left - 24) / (bounds.width - 36);
  selectedSample = Math.max(0, Math.min(historyMinutes, Math.round(fraction * historyMinutes)));
  drawCharts();
});
const clearSample = () => { selectedSample = null; drawCharts(); };
chart.addEventListener("pointerleave", clearSample);
chart.addEventListener("blur", clearSample);
chart.addEventListener("keydown", (event) => {
  const move = { ArrowLeft: -1, ArrowRight: 1 }[event.key];
  if (!move) return;
  event.preventDefault();
  selectedSample = Math.max(0, Math.min(historyMinutes, (selectedSample ?? historyMinutes) + move));
  drawCharts();
});
const resize = new ResizeObserver(drawCharts);
resize.observe(spark);
resize.observe(chart);
window.setInterval(() => { if (!paused) step(1); }, 1000);
render();
