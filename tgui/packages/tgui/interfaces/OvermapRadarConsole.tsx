import { useEffect, useMemo, useRef, useState } from 'react';
import {
  Button,
  Input,
  LabeledList,
  NoticeBox,
  Section,
  Slider,
  Stack,
} from 'tgui-core/components';
import { clamp } from 'tgui-core/math';
import type { BooleanLike } from 'tgui-core/react';

import { useBackend } from '../backend';
import { Window } from '../layouts';

type RadarContact = {
  id: string;
  track: string;
  name: string;
  type: string;
  type_label?: string;
  x: number;
  y: number;
  bearing: number;
  distance: number;
  /// Server clock stamp of the last sweep that painted this contact, in deciseconds. Ages are derived
  /// from this against `serverTime` rather than sent per contact, so a contact whose position has not
  /// changed serialises identically between pushes.
  last_seen: number;
};

type Data = {
  on: BooleanLike;
  viewerX: number | null;
  viewerY: number | null;
  gridSize: number;
  /// Server clock at the moment this payload was built, in deciseconds. The client advances it locally
  /// so contact fades keep moving between pushes instead of only on one.
  serverTime: number;
  bearing: number;
  arcWidth: number;
  animBearing: number;
  animArc: number;
  range: number;
  minArc: number;
  wideRange: number;
  narrowRange: number;
  scanReady: BooleanLike;
  sweepLeft: number;
  scanCooldown: number;
  hasDish: BooleanLike;
  selectedId: string | null;
  /// One batch, not the whole picture. The console pays its contact list out a batch per push to keep
  /// any single write small, so these accumulate across pushes sharing a `drainSeq`.
  contacts: RadarContact[];
  /// Payout cycle this batch belongs to. A change means a fresh picture is being sent.
  drainSeq: number;
  /// Whether this batch completes the cycle, at which point anything not resent has gone away.
  drainDone: BooleanLike;
  /// Contacts in the whole cycle, for reporting progress while a picture is still arriving.
  contactTotal: number;
  decay: number;
};

type CanvasPoint = {
  x: number;
  y: number;
};

const CONTACT_COLOR: Record<string, string> = {
  star: '#ffb040',
  planet: '#6ec070',
  moon: '#c8c8d0',
  celestial: '#e0c878',
  ship: '#7ec8e3',
  fighter: '#9ad4e8',
  frigate: '#5aa8d0',
  capital: '#4080c0',
  station: '#f0d060',
  mining: '#e09040',
  installation: '#d0c070',
  depot: '#c8b050',
  site: '#a0c878',
  open_space: '#8890a0',
  level: '#f0d060',
  dynamic: '#e8b830',
  meteor: '#c06040',
  electric: '#50d0f0',
  emp: '#a070e0',
  radiation: '#70e050',
  event: '#e05050',
  unknown: '#c0c0c0',
};

const formatScanAge = (ageDs: number) => `${Math.round(ageDs / 10)}s`;

/// How stale a contact is, in deciseconds, against a server clock reading.
const contactAge = (contact: RadarContact, serverNow: number) =>
  Math.max(0, serverNow - contact.last_seen);

type ContactAssembly = {
  seq: number | null;
  staging: Record<string, RadarContact>;
  displayed: Record<string, RadarContact>;
};

/**
 * Reassembles the console's batched contact payout into one picture.
 *
 * The console sends a slice of its contacts per push so that no single write to the game client is
 * large enough to hitch it. That means a payload is not the whole truth, and a contact's absence from
 * one cannot be read as the contact having gone away.
 *
 * So batches sharing a cycle are staged, and only a cycle that reports itself complete is promoted to
 * the displayed picture. Anything missing from a complete cycle has genuinely gone and is retired
 * then. A cycle abandoned partway through, which is what a fresh sweep mid-payout causes, is dropped
 * rather than merged, so a stale half-picture can never be mistaken for a current one.
 */
const useAssembledContacts = (data: Data): RadarContact[] => {
  const [assembly, setAssembly] = useState<ContactAssembly>({
    seq: null,
    staging: {},
    displayed: {},
  });

  useEffect(() => {
    setAssembly((prev) => {
      const staging = prev.seq === data.drainSeq ? { ...prev.staging } : {};
      for (const contact of data.contacts) {
        // This runs inside a state update, so anything thrown here takes the whole window down with
        // a fatal exception rather than dropping one contact. A batch is worth less than the console.
        if (contact) {
          staging[contact.id] = contact;
        }
      }
      return {
        seq: data.drainSeq,
        staging,
        displayed: data.drainDone ? staging : prev.displayed,
      };
    });
  }, [data.contacts, data.drainSeq, data.drainDone]);

  // Mid-cycle, what has arrived sits on top of the last complete picture, so a busy sector paints in
  // nearest first rather than blanking until the final batch lands.
  return useMemo(
    () => Object.values({ ...assembly.displayed, ...assembly.staging }),
    [assembly],
  );
};

const CANVAS_SIZE = 512;
const CONTACT_HIT_PX = 16;
const DS_TO_MS = 100;
const OVERMAP_SCAN_FALLBACK_MS = 5000;

const contactColor = (type: string) => CONTACT_COLOR[type] ?? '#c0c0c0';

const toCanvasRad = (navDeg: number) => ((navDeg - 90) * Math.PI) / 180;

const canvasPoint = (
  canvas: HTMLCanvasElement,
  event: { clientX: number; clientY: number },
): CanvasPoint | null => {
  const rect = canvas.getBoundingClientRect();
  if (rect.width <= 0 || rect.height <= 0) {
    return null;
  }
  return {
    x: ((event.clientX - rect.left) / rect.width) * CANVAS_SIZE,
    y: ((event.clientY - rect.top) / rect.height) * CANVAS_SIZE,
  };
};

const originOnCanvas = (viewerX: number, viewerY: number, gridSize: number) => {
  const scale = CANVAS_SIZE / gridSize;
  return {
    x: (viewerX - 0.5) * scale,
    y: CANVAS_SIZE - (viewerY - 0.5) * scale,
    scale,
  };
};

const bearingFromPointer = (
  canvas: HTMLCanvasElement,
  event: { clientX: number; clientY: number },
  viewerX: number,
  viewerY: number,
  gridSize: number,
) => {
  const point = canvasPoint(canvas, event);
  if (!point) {
    return null;
  }
  const origin = originOnCanvas(viewerX, viewerY, gridSize);
  const deg =
    (Math.atan2(point.x - origin.x, origin.y - point.y) * 180) / Math.PI;
  return Math.round(((deg % 360) + 360) % 360);
};

const contactAtPointer = (
  canvas: HTMLCanvasElement,
  event: { clientX: number; clientY: number },
  data: Data,
  contacts: RadarContact[],
) => {
  if (data.viewerX === null || data.viewerY === null) {
    return null;
  }
  const point = canvasPoint(canvas, event);
  if (!point) {
    return null;
  }
  const origin = originOnCanvas(data.viewerX, data.viewerY, data.gridSize);
  let closest: RadarContact | null = null;
  let closestDist = CONTACT_HIT_PX;
  for (const contact of contacts) {
    const x = (contact.x - 0.5) * origin.scale;
    const y = CANVAS_SIZE - (contact.y - 0.5) * origin.scale;
    const dist = Math.hypot(point.x - x, point.y - y);
    if (dist <= closestDist) {
      closest = contact;
      closestDist = dist;
    }
  }
  return closest;
};

const drawRadar = (
  canvas: HTMLCanvasElement,
  data: Data,
  sweepT: number | null,
  serverNow: number,
  contacts: RadarContact[],
) => {
  const ctx = canvas.getContext('2d');
  if (!ctx) {
    return;
  }
  const {
    gridSize,
    viewerX,
    viewerY,
    bearing,
    arcWidth,
    range,
    decay,
    selectedId,
  } = data;

  if (viewerX === null || viewerY === null) {
    return;
  }

  ctx.fillStyle = '#0b1018';
  ctx.fillRect(0, 0, CANVAS_SIZE, CANVAS_SIZE);
  const { x: originX, y: originY, scale } = originOnCanvas(
    viewerX,
    viewerY,
    gridSize,
  );

  ctx.strokeStyle = '#1c2a3a';
  ctx.lineWidth = 1;
  for (let i = 0; i <= gridSize; i += 8) {
    ctx.beginPath();
    ctx.moveTo(i * scale, 0);
    ctx.lineTo(i * scale, CANVAS_SIZE);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(0, CANVAS_SIZE - i * scale);
    ctx.lineTo(CANVAS_SIZE, CANVAS_SIZE - i * scale);
    ctx.stroke();
  }

  const start = toCanvasRad(bearing - arcWidth / 2);
  const end = toCanvasRad(bearing + arcWidth / 2);
  const radius = range * scale;

  ctx.fillStyle = 'rgba(80, 160, 220, 0.12)';
  ctx.beginPath();
  ctx.moveTo(originX, originY);
  ctx.arc(originX, originY, radius, start, end, false);
  ctx.closePath();
  ctx.fill();

  ctx.strokeStyle = 'rgba(80, 160, 220, 0.55)';
  ctx.beginPath();
  ctx.arc(originX, originY, radius, start, end, false);
  ctx.stroke();

  if (sweepT !== null) {
    const sweepStartNav = bearing - arcWidth / 2;
    const sweepNowNav = sweepStartNav + arcWidth * sweepT;
    const sweepStart = toCanvasRad(sweepStartNav);
    const sweepNow = toCanvasRad(sweepNowNav);
    ctx.fillStyle = 'rgba(120, 210, 255, 0.16)';
    ctx.beginPath();
    ctx.moveTo(originX, originY);
    ctx.arc(originX, originY, radius, sweepStart, sweepNow, false);
    ctx.closePath();
    ctx.fill();
    ctx.strokeStyle = 'rgba(200, 240, 255, 0.95)';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(originX, originY);
    ctx.lineTo(
      originX + Math.cos(sweepNow) * radius,
      originY + Math.sin(sweepNow) * radius,
    );
    ctx.stroke();
  }

  ctx.fillStyle = '#f4f4f4';
  ctx.beginPath();
  ctx.arc(originX, originY, 4, 0, Math.PI * 2);
  ctx.fill();

  for (const contact of contacts) {
    const x = (contact.x - 0.5) * scale;
    const y = CANVAS_SIZE - (contact.y - 0.5) * scale;
    const age = contactAge(contact, serverNow);
    const fade = Math.max(0.25, 1 - age / decay);
    ctx.globalAlpha = fade;
    ctx.fillStyle = contactColor(contact.type);
    const size = contact.id === selectedId ? 6 : 4;
    ctx.beginPath();
    ctx.arc(x, y, size, 0, Math.PI * 2);
    ctx.fill();
    if (contact.id === selectedId) {
      ctx.strokeStyle = '#ffffff';
      ctx.lineWidth = 1;
      ctx.stroke();
    }
    ctx.fillStyle = '#e8f4ff';
    ctx.font = '12px monospace';
    ctx.textBaseline = 'bottom';
    ctx.fillText(contact.track, x + 8, y - 4);
    ctx.fillStyle = '#9ab4c8';
    ctx.font = '10px monospace';
    ctx.textBaseline = 'top';
    ctx.fillText(formatScanAge(age), x + 8, y + 4);
    ctx.globalAlpha = 1;
  }
};

export const OvermapRadarConsole = () => {
  const { act, data } = useBackend<Data>();
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const dataRef = useRef(data);
  const draggingRef = useRef(false);
  const sweepEndMs = useRef<number | null>(null);
  const sweepDurationMs = useRef(OVERMAP_SCAN_FALLBACK_MS);
  dataRef.current = data;

  // Last server clock reading and the local time we took it at, so the clock can be advanced between
  // pushes. The backend no longer sends an age per contact, and no longer pushes on a timer.
  const clockRef = useRef({
    serverTime: data.serverTime,
    takenAtMs: performance.now(),
  });
  useEffect(() => {
    clockRef.current = {
      serverTime: data.serverTime,
      takenAtMs: performance.now(),
    };
  }, [data.serverTime]);

  const serverNow = () => {
    const { serverTime, takenAtMs } = clockRef.current;
    return serverTime + (performance.now() - takenAtMs) / DS_TO_MS;
  };

  // The track list prints ages as text, which React only repaints when it re-renders. Pushes are no
  // longer on a timer, so tick locally to keep those labels honest. A re-render a second is far
  // cheaper than the payload it replaces, and the scope itself is already redrawn by the RAF loop.
  const [, setAgeTick] = useState(0);
  useEffect(() => {
    const timer = setInterval(() => setAgeTick((prev) => prev + 1), 1000);
    return () => clearInterval(timer);
  }, []);

  const contacts = useAssembledContacts(data);
  const contactsRef = useRef(contacts);
  contactsRef.current = contacts;

  const selected = useMemo(
    () => contacts.find((contact) => contact.id === data.selectedId),
    [contacts, data.selectedId],
  );

  useEffect(() => {
    const remainingMs = data.sweepLeft * DS_TO_MS;
    if (!data.scanReady && remainingMs > 0) {
      const inferredEnd = performance.now() + remainingMs;
      if (
        sweepEndMs.current === null ||
        inferredEnd > sweepEndMs.current + 200
      ) {
        sweepEndMs.current = inferredEnd;
        sweepDurationMs.current = data.scanCooldown * DS_TO_MS;
      }
    }
    if (data.scanReady) {
      sweepEndMs.current = null;
    }
  }, [data.scanReady, data.sweepLeft, data.scanCooldown]);

  useEffect(() => {
    let frame = 0;
    const tick = () => {
      const canvas = canvasRef.current;
      if (canvas) {
        drawRadar(
          canvas,
          dataRef.current,
          currentSweepProgress(),
          serverNow(),
          contactsRef.current,
        );
      }
      frame = requestAnimationFrame(tick);
    };
    const currentSweepProgress = () => {
      if (sweepEndMs.current === null) {
        return null;
      }
      const left = sweepEndMs.current - performance.now();
      if (left <= 0) {
        return 1;
      }
      return clamp(1 - left / sweepDurationMs.current, 0, 1);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, []);

  const applyBearing = (event: { clientX: number; clientY: number }) => {
    const canvas = canvasRef.current;
    if (!canvas || data.viewerX === null || data.viewerY === null) {
      return;
    }
    const next = bearingFromPointer(
      canvas,
      event,
      data.viewerX,
      data.viewerY,
      data.gridSize,
    );
    if (next === null) {
      return;
    }
    act('set_bearing', { bearing: next });
  };

  const startSweep = () => {
    sweepEndMs.current = performance.now() + data.scanCooldown * DS_TO_MS;
    sweepDurationMs.current = data.scanCooldown * DS_TO_MS;
    act('sweep');
  };

  return (
    <Window width={980} height={780} title="Deep-Space Radar">
      <Window.Content>
        <Stack fill>
          <Stack.Item grow>
            <Stack fill vertical>
              {!data.on && <NoticeBox danger>Console unpowered.</NoticeBox>}
              {!data.hasDish && (
                <NoticeBox>No linked dish on this powernet.</NoticeBox>
              )}
              <Stack.Item>
                <Section title="Sweep">
                  <LabeledList>
                    <LabeledList.Item label="Bearing" verticalAlign="middle">
                      <Slider
                        minValue={0}
                        maxValue={359}
                        step={1}
                        stepPixelSize={2}
                        tickWhileDragging
                        value={data.bearing}
                        unit="°"
                        width="100%"
                        onChange={(_e, value) =>
                          act('set_bearing', { bearing: value })
                        }
                      />
                    </LabeledList.Item>
                    <LabeledList.Item label="Arc" verticalAlign="middle">
                      <Slider
                        minValue={data.minArc}
                        maxValue={360}
                        step={5}
                        stepPixelSize={4}
                        tickWhileDragging
                        value={data.arcWidth}
                        unit="°"
                        width="100%"
                        onChange={(_e, value) =>
                          act('set_arc', { arc: value })
                        }
                      />
                    </LabeledList.Item>
                    <LabeledList.Item label="Max range">
                      {data.range} tiles (wide {data.wideRange} / narrow{' '}
                      {data.narrowRange})
                    </LabeledList.Item>
                  </LabeledList>
                  <Stack mt={1}>
                    <Stack.Item grow>
                      <Button
                        fluid
                        icon="satellite-dish"
                        disabled={
                          !data.scanReady || !data.hasDish || !data.on
                        }
                        onClick={startSweep}
                      >
                        {data.scanReady ? 'Sweep' : 'Sweeping...'}
                      </Button>
                    </Stack.Item>
                    <Stack.Item grow>
                      <Button
                        fluid
                        icon="print"
                        disabled={!selected}
                        onClick={() => act('print_contact')}
                      >
                        Print contact
                      </Button>
                    </Stack.Item>
                    <Stack.Item grow>
                      <Button
                        fluid
                        icon="clipboard"
                        onClick={() => act('print_transcript')}
                      >
                        Print transcript
                      </Button>
                    </Stack.Item>
                  </Stack>
                </Section>
              </Stack.Item>
              <Stack.Item grow basis={0} minHeight={0}>
                <Section fill title="Scope">
                  <div
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      height: '100%',
                      minHeight: 0,
                      overflow: 'hidden',
                    }}
                  >
                    <canvas
                      ref={canvasRef}
                      width={CANVAS_SIZE}
                      height={CANVAS_SIZE}
                      onPointerDown={(event) => {
                        const canvas = event.currentTarget;
                        const hit = contactAtPointer(
                          canvas,
                          event,
                          data,
                          contacts,
                        );
                        if (hit) {
                          act('select', { id: hit.id });
                          return;
                        }
                        canvas.setPointerCapture(event.pointerId);
                        draggingRef.current = true;
                        applyBearing(event);
                      }}
                      onPointerMove={(event) => {
                        if (!draggingRef.current) {
                          return;
                        }
                        applyBearing(event);
                      }}
                      onPointerUp={() => {
                        draggingRef.current = false;
                      }}
                      onPointerCancel={() => {
                        draggingRef.current = false;
                      }}
                      onWheel={(event) => {
                        event.preventDefault();
                        const next = clamp(
                          data.arcWidth + (event.deltaY > 0 ? 5 : -5),
                          data.minArc,
                          360,
                        );
                        act('set_arc', { arc: next });
                      }}
                      style={{
                        display: 'block',
                        width: 'auto',
                        height: 'auto',
                        maxWidth: '100%',
                        maxHeight: '100%',
                        objectFit: 'contain',
                        imageRendering: 'pixelated',
                        cursor: 'crosshair',
                      }}
                    />
                  </div>
                </Section>
              </Stack.Item>
            </Stack>
          </Stack.Item>
          <Stack.Item width={26}>
            <Section fill scrollable title="Tracks">
              {!contacts.length && 'No last-seen contacts.'}
              {contacts.length < data.contactTotal &&
                `Receiving ${contacts.length} of ${data.contactTotal}...`}
              {contacts.map((contact) => (
                <Stack key={contact.id} mb={0.5}>
                  <Stack.Item>
                    <Input
                      width="4.5em"
                      value={contact.track}
                      maxLength={12}
                      onChange={(value) =>
                        act('set_track', { id: contact.id, track: value })
                      }
                    />
                  </Stack.Item>
                  <Stack.Item grow>
                    <Button
                      fluid
                      selected={contact.id === data.selectedId}
                      onClick={() => act('select', { id: contact.id })}
                    >
                      {contact.name || 'Unknown'} ·{' '}
                      {contact.type_label || contact.type} · {contact.x},
                      {contact.y}
                      <br />
                      {contact.bearing}° / {contact.distance} ·{' '}
                      {formatScanAge(contactAge(contact, serverNow()))}
                    </Button>
                  </Stack.Item>
                </Stack>
              ))}
            </Section>
          </Stack.Item>
        </Stack>
      </Window.Content>
    </Window>
  );
};
