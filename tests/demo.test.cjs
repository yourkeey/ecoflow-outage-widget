const test = require("node:test");
const assert = require("node:assert/strict");
const sim = require("../demo/simulation.js");

test("automatic power switches at the scheduled start and end", () => {
  const state = sim.createSimulation();
  assert.equal(sim.scheduleAt(state.minute).minutes, 28);
  sim.advance(state, 28);
  assert.equal(sim.telemetry(state).onGrid, false);
  assert.equal(sim.telemetry(state).input, 0);
  const energy = state.energy;
  sim.advance(state, 120);
  assert.ok(state.energy < energy);
  assert.equal(sim.telemetry(state).onGrid, true);
  assert.ok(sim.telemetry(state).input > sim.telemetry(state).output);
  assert.equal(sim.scheduleAt(22 * 60).tomorrow, true);
});

test("an outage can empty the battery, which recharges once power returns", () => {
  const state = sim.createSimulation();
  sim.advance(state, sim.scheduleAt(state.minute).minutes);
  state.energy = 2;
  assert.ok(sim.telemetry(state).runtime > 0);
  sim.advance(state, 10);
  assert.equal(state.energy, 0);
  assert.equal(sim.telemetry(state).runtime, null);
  assert.equal(sim.telemetry(state).output, 0);
  sim.advance(state, sim.scheduleAt(state.minute).minutes);
  assert.equal(sim.telemetry(state).onGrid, true);
  sim.advance(state, 30);
  assert.ok(state.energy > 0);
  // There is a second evening outage before the longer overnight charging window.
  sim.advance(state, 21 * 60 - state.minute);
  const estimate = sim.telemetry(state).timeToFull;
  assert.ok(estimate > 0 && estimate < sim.scheduleAt(state.minute).minutes);
  sim.advance(state, estimate);
  assert.equal(state.energy, sim.capacity);
  assert.equal(sim.telemetry(state).online, true);
});

test("load history keeps a rolling 45-minute window across midnight", () => {
  const state = sim.createSimulation();
  sim.advance(state, sim.minutesPerDay - state.minute + 15);
  assert.equal(state.history.at(-1).minute, state.minute);
  assert.equal(state.history.at(-1).minute - state.history[0].minute, 45);
  assert.ok(new Set(state.history.map((sample) => sample.output)).size > 1);
});
