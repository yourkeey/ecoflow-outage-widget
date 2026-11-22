"use strict";

const sim = RiverSimulation;
const element = (id) => document.getElementById(id);
const write = (id, text) => { element(id).textContent = text; };
const chart = element("history-chart");
const spark = element("load-spark");
const historyMinutes = sim.historyMinutes;
const mint = "#72e3bc";
const dateLabels = { today: "Сегодня", tomorrow: "Завтра", latest: "Последний график" };
const state = sim.createSimulation();
let scheduleDay = "today";
let selectedSample = null;

function duration(minutes) {
  return sim.duration(minutes).replace("h", " ч").replace("m", " мин");
}

function timeRange([start, end]) {
  return sim.clock(start) + " — " + sim.clock(end);
}

function updateCharge(value) {
  const progress = element("battery-progress");
  write("charge", Math.round(value) + " %");
  progress.setAttribute("aria-valuenow", String(Math.round(value)));
  progress.dataset.tone = value < 20 ? "warning" : "normal";
  element("battery-fill").style.width = value + "%";
}

function render() {
  const live = sim.telemetry(state);
  const day = Math.floor(state.minute / sim.minutesPerDay);
  const time = state.minute % sim.minutesPerDay;
  write("clock", "Демо · " + sim.clock(time) + " · 1 мин/сек");
  write("power-status", "Обновлено " + sim.clock(time) + ":00");
  updateCharge(state.energy / sim.capacity * 100);
  write("input-watts", live.input + " Вт");
  write("output-watts", live.output + " Вт");
  const remaining = live.onGrid ? live.timeToFull : live.runtime;
  write("estimate", remaining > 0 ? "Осталось: " + duration(remaining) : "Оставшееся время: —");
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

function drawLoadLine(context, samples, x, y, width) {
  context.beginPath();
  context.moveTo(x(0), y(samples[0].output));
  samples.slice(1).forEach((sample, index) => {
    context.lineTo(x(index + 1), y(sample.output));
  });
  context.strokeStyle = mint;
  context.lineWidth = width;
  context.lineJoin = "round";
  context.stroke();
}

function drawSpark(samples, max) {
  const plot = getPlot(spark);
  if (!plot) return;
  const { width, height, context } = plot;
  const last = samples.length - 1;
  const x = (index) => 2 + (width - 5) * index / last;
  // Leave a little space above the data line for the most recent marker.
  const y = (value) => height - 2 - (height - 6) * value / max;
  context.fillStyle = "#b3c5d788";
  context.fillRect(2, height - 1, width - 5, 1);
  drawLoadLine(context, samples, x, y, 1.4);
  context.beginPath();
  context.arc(x(last), y(samples[last].output), 2, 0, Math.PI * 2);
  context.fillStyle = "#abefd7";
  context.fill();
}

function drawHistory(samples, max, min, peak) {
  const plot = getPlot(chart);
  if (!plot) return;
  const { width, height, context } = plot;
  const left = 24;
  const right = width - 12;
  const top = 8;
  const bottom = height - 18;
  const ticks = [0, max / 2, max];
  const x = (index) => left + (right - left) * index / historyMinutes;
  const y = (value) => bottom - (bottom - top) * value / max;

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

  drawLoadLine(context, samples, x, y, 1.6);
  write("chart-stats", "Мин. " + min + " Вт · пик " + peak + " Вт");
  if (selectedSample === null) {
    write("chart-value", "Нагрузка за последние 45 минут");
    return;
  }

  const sample = samples[selectedSample];
  context.fillStyle = "#edf4f8";
  context.fillRect(x(selectedSample), top, 1, bottom - top);
  write("chart-value", sim.clock(sample.minute % sim.minutesPerDay) + " · " + sample.output + " Вт");
}

function drawCharts() {
  const samples = state.history;
  const loads = samples.map((sample) => sample.output);
  const peak = Math.max(...loads);
  const max = Math.max(50, Math.ceil(peak / 50) * 50);
  drawSpark(samples, max);
  drawHistory(samples, max, Math.min(...loads), peak);
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

bindSegments("main-tabs", showPanel);
bindSegments("schedule-controls", (value) => { scheduleDay = value; });

element("open-schedule").addEventListener("click", () => {
  showPanel("schedule");
  element("main-tabs").querySelector('[data-value="schedule"]').focus();
  render();
});
element("open-history").addEventListener("click", () => {
  const history = element("load-history");
  const open = history.hidden;
  history.hidden = !open;
  element("open-history").setAttribute("aria-expanded", String(open));
  if (open) chart.focus();
  drawCharts();
});
element("hide-widget").addEventListener("click", () => setWidgetVisible(false));
element("restore-widget").addEventListener("click", () => setWidgetVisible(true));
element("open-settings").addEventListener("click", () => element("settings").showModal());
element("close-settings").addEventListener("click", () => element("settings").close());

function step() {
  sim.advance(state);
  render();
}

for (const button of document.querySelectorAll(".refresh")) {
  button.addEventListener("click", step);
}

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
window.setInterval(step, 1000);
render();
