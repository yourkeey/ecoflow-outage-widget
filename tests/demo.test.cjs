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

test("manual outage drains the battery, then grid restores telemetry", () => {
  const state = sim.createSimulation();
  const coding = sim.telemetry(state);
  state.power = "outage";
  state.workload = "render";
  const rendering = sim.telemetry(state);
  assert.ok(rendering.cpu > coding.cpu && rendering.gpu > coding.gpu);
  assert.ok(rendering.output > coding.output);
  sim.advance(state, 200);
  assert.equal(state.energy, 0);
  assert.equal(sim.telemetry(state).cpu, null);
  assert.equal(sim.telemetry(state).output, 0);
  const weekly = state.weekly.left;
  sim.advance(state, 10);
  assert.equal(state.weekly.left, weekly);
  state.power = "grid";
  const estimate = sim.telemetry(state).timeToFull;
  sim.advance(state, estimate);
  assert.equal(state.energy, sim.capacity);
  assert.equal(sim.telemetry(state).online, true);
});

test("usage resets on schedule and telemetry keeps a rolling hour", () => {
  const state = sim.createSimulation();
  sim.advance(state, 30);
  assert.ok(state.session.left < 38 && state.weekly.left < 64);
  sim.advance(state, state.session.reset - state.minute);
  assert.equal(state.session.left, 100);
  sim.advance(state, state.weekly.reset - state.minute);
  assert.equal(state.weekly.left, 100);
  assert.equal(state.history.at(-1).minute - state.history[0].minute, 60);
  assert.ok(new Set(state.history.map((sample) => sample.cpu)).size > 1);
});
