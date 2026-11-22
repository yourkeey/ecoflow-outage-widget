"use strict";

const RiverSimulation = (() => {
  const capacity = 768;
  const minutesPerDay = 1440;
  const efficiency = 0.9;
  const historyLength = 61;
  const profiles = {
    idle: { watts: 64, cpuTemp: 40, gpuTemp: 38, cpuLoad: 9, gpuLoad: 8, aiRate: 0 },
    dev: { watts: 128, cpuTemp: 58, gpuTemp: 49, cpuLoad: 42, gpuLoad: 22, aiRate: 0.45 },
    render: { watts: 252, cpuTemp: 79, gpuTemp: 75, cpuLoad: 86, gpuLoad: 92, aiRate: 0.85 },
  };
  const schedules = [
    [[360, 450], [900, 1020], [1170, 1260]],
    [[510, 630], [810, 930], [1200, 1290]],
  ];

  function windows(day) {
    return schedules[day % schedules.length];
  }

  function clock(minute) {
    const hour = String(Math.floor(minute / 60)).padStart(2, "0");
    const remainder = String(minute % 60).padStart(2, "0");
    return hour + ":" + remainder;
  }

  function duration(minutes) {
    const total = Math.ceil(minutes);
    const hours = Math.floor(total / 60);
    const rest = total % 60;
    return hours > 0 ? hours + "h " + rest + "m" : rest + "m";
  }

  function scheduleAt(minute) {
    const day = Math.floor(minute / minutesPerDay);
    const time = minute % minutesPerDay;
    const current = windows(day).find(([start, end]) => time >= start && time < end);
    if (current) {
      return { active: true, time: current[1], minutes: current[1] - time, tomorrow: false };
    }
    const upcoming = windows(day).find(([start]) => start > time);
    const next = upcoming ?? windows(day + 1)[0];
    return {
      active: false,
      time: next[0],
      minutes: next[0] - time + (upcoming ? 0 : minutesPerDay),
      tomorrow: !upcoming,
    };
  }

  function telemetry(state, minute = state.minute) {
    const onGrid = state.power === "grid" || (state.power === "auto" && !scheduleAt(minute).active);
    const online = onGrid || state.energy > 0;
    const profile = profiles[state.workload];
    const drift = 0.65 * Math.sin(minute / 4.8) + 0.35 * Math.cos(minute / 2.4);
    const output = online ? Math.round(profile.watts + drift * 18) : 0;
    const remainingEnergy = capacity - state.energy;
    const chargeWatts = onGrid && remainingEnergy > 0.01 ? Math.min(300, 55 + remainingEnergy * 1.6) : 0;
    return {
      minute, onGrid, online, output, chargeWatts,
      input: onGrid ? output + Math.round(chargeWatts) : 0,
      cpu: online ? Math.round(profile.cpuTemp + drift * 5) : null,
      gpu: online ? Math.round(profile.gpuTemp + drift * 4) : null,
      cpuLoad: online ? Math.round(profile.cpuLoad + drift * 8) : null,
      gpuLoad: online ? Math.round(profile.gpuLoad - drift * 7) : null,
      runtime: !onGrid && online ? state.energy * efficiency * 60 / output : null,
      // Taper near full charge, so use the same model as the minute-by-minute simulation.
      timeToFull: chargeWatts ? estimateCharge(remainingEnergy) : 0,
    };
  }

  function estimateCharge(energy) {
    let minutes = 0;
    while (energy > 0.01) {
      energy -= Math.min(300, 55 + energy * 1.6) * efficiency / 60;
      minutes += 1;
    }
    return minutes;
  }

  function createSimulation() {
    const minute = 14 * 60 + 32;
    const state = {
      minute,
      power: "auto",
      workload: "dev",
      energy: capacity * 0.76,
      session: { left: 38, reset: minute + 108, period: 300 },
      weekly: { left: 64, reset: minute + 896, period: 7 * minutesPerDay },
    };
    state.history = Array.from({ length: historyLength }, (_, index) =>
      telemetry(state, minute + index - historyLength + 1));
    return state;
  }

  function advance(state, minutes = 1) {
    for (let index = 0; index < minutes; index += 1) {
      const sample = telemetry(state);
      const delta = sample.onGrid ? sample.chargeWatts * efficiency : -sample.output / efficiency;
      state.energy = Math.max(0, Math.min(capacity, state.energy + delta / 60));
      if (capacity - state.energy <= 0.01) state.energy = capacity;
      state.minute += 1;

      const usage = sample.online ? profiles[state.workload].aiRate : 0;
      for (const [budget, rate] of [[state.session, usage], [state.weekly, usage / 12]]) {
        if (state.minute === budget.reset) {
          budget.left = 100;
          budget.reset += budget.period;
        } else {
          budget.left = Math.max(0, budget.left - rate);
        }
      }

      state.history.push(telemetry(state));
      if (state.history.length > historyLength) state.history.shift();
    }
  }

  return { capacity, minutesPerDay, clock, duration, windows, scheduleAt, telemetry, createSimulation, advance };
})();

if (typeof module !== "undefined") module.exports = RiverSimulation;
