"use strict";

const RiverSimulation = (() => {
  const capacity = 768;
  const minutesPerDay = 1440;
  const efficiency = 0.9;
  const historyMinutes = 45;
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
    const onGrid = !scheduleAt(minute).active;
    const online = onGrid || state.energy > 0;
    const drift = 0.65 * Math.sin(minute / 4.8) + 0.35 * Math.cos(minute / 2.4);
    const output = online ? Math.round(84 + drift * 18) : 0;
    const remainingEnergy = capacity - state.energy;
    const chargeWatts = onGrid && remainingEnergy > 0.01 ? Math.min(300, 55 + remainingEnergy * 1.6) : 0;
    return {
      minute, onGrid, online, output, chargeWatts,
      input: onGrid ? output + Math.round(chargeWatts) : 0,
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
    const state = { minute, energy: capacity * 0.9 };
    state.history = Array.from({ length: historyMinutes + 1 }, (_, index) =>
      telemetry(state, minute + index - historyMinutes));
    return state;
  }

  function advance(state, minutes = 1) {
    for (let index = 0; index < minutes; index += 1) {
      const sample = telemetry(state);
      const delta = sample.onGrid ? sample.chargeWatts * efficiency : -sample.output / efficiency;
      state.energy = Math.max(0, Math.min(capacity, state.energy + delta / 60));
      if (capacity - state.energy <= 0.01) state.energy = capacity;
      state.minute += 1;

      state.history.push(telemetry(state));
      if (state.history.length > historyMinutes + 1) state.history.shift();
    }
  }

  return { capacity, historyMinutes, minutesPerDay, clock, duration, windows, scheduleAt, telemetry, createSimulation, advance };
})();

if (typeof module !== "undefined") module.exports = RiverSimulation;
