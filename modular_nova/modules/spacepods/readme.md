# Title: Spacepods

MODULE ID: SPACEPODS

## Description

Ports the single-occupant "ball" spacepod from Whitesands as a local-Z utility
vehicle for EVA salvage, mining, and patrol. Includes:

- `/obj/spacepod`: a 2x2 piloted pod with velocity-based physics (drag, thrust,
  rotation, and high-speed collision damage) ticked by `SSfastprocess`.
- A 13-state build/deconstruct chain: rod frames assemble into a bare pod, then
  wires, mainboard, core, bulkhead, and armor plating are added with tools.
- Modular equipment: weapons (disabler, laser, kinetic accelerator, plasma
  cutter), cargo systems (crate/ore storage, passenger seat), a tracker, and a
  keyed lock.
- Protolathe/imprinter designs and a `Spacepod Construction` techweb node.
- Prebuilt security and jousting pods for mapping and events.

Pilots aim and fire mounted weapons by clicking (via `click_intercept`), and
brakes, lights, locks, and nearby pod-door toggles are exposed as pod verbs.

## Credits

Original system by the Whitesands/Paradise spacepod authors. Ported and
modernized for ss13-blastwave.
