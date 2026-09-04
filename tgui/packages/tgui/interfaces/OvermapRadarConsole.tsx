import { useEffect, useMemo, useRef } from 'react';
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
  affiliation: string;
  last_seen: number;
  age: number;
  compression: number;
};

type Data = {
  on: BooleanLike;
  viewerX: number | null;
  viewerY: number | null;
  gridSize: number;
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
  contacts: RadarContact[];
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
  for (const contact of data.contacts) {
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
    contacts,
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
    const fade = Math.max(0.25, 1 - contact.age / decay);
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
    ctx.fillText(formatScanAge(contact.age), x + 8, y + 4);
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

  const selected = useMemo(
    () => data.contacts.find((contact) => contact.id === data.selectedId),
    [data.contacts, data.selectedId],
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
        drawRadar(canvas, dataRef.current, currentSweepProgress());
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
                        const hit = contactAtPointer(canvas, event, data);
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
              {!data.contacts.length && 'No last-seen contacts.'}
              {data.contacts.map((contact) => (
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
                      {formatScanAge(contact.age)}
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
