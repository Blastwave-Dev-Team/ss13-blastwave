import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

const HELM_DEBOUNCE_MS = 100;

function useDebouncedCallback<T extends (...args: any[]) => void>(
  callback: T,
  delay: number,
): T {
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const latestArgs = useRef<Parameters<T>>();
  const latestCb = useRef(callback);
  latestCb.current = callback;

  return useMemo(
    () =>
      ((...args: Parameters<T>) => {
        latestArgs.current = args;
        if (timer.current === null) {
          latestCb.current(...args);
          timer.current = setTimeout(() => {
            timer.current = null;
            if (latestArgs.current) {
              latestCb.current(...latestArgs.current);
            }
          }, delay);
        }
      }) as T,
    [delay],
  );
}

type NavBallProps = {
  actualAngle: number;
  actualSpeed: number;
  desiredAngle: number;
  desiredThrottle: number;
  locked: boolean;
  disabled: boolean;
  onSetDesired: (angle: number, throttle: number) => void;
  onAllStop: () => void;
  onToggleLock: () => void;
};

const CX = 120;
const CY = 120;
const RADIUS = 100;

const COMPASS = [
  { label: 'N', angle: -Math.PI / 2 },
  { label: 'NE', angle: -Math.PI / 4 },
  { label: 'E', angle: 0 },
  { label: 'SE', angle: Math.PI / 4 },
  { label: 'S', angle: Math.PI / 2 },
  { label: 'SW', angle: (Math.PI * 3) / 4 },
  { label: 'W', angle: Math.PI },
  { label: 'NW', angle: (-Math.PI * 3) / 4 },
];

const WASD_RAMP_TIME = 1500;
const WASD_EXPONENT = 2.2;
const WASD_MAX_RATE = 0.02;
const YAW_MAX_RATE = 0.04;

function drawBall(
  ctx: CanvasRenderingContext2D,
  actualAngle: number,
  actualSpeed: number,
  desiredAngle: number,
  desiredThrottle: number,
  focused: boolean,
) {
  ctx.clearRect(0, 0, 240, 240);

  const bg = ctx.createRadialGradient(CX, CY, 0, CX, CY, RADIUS + 10);
  bg.addColorStop(0, '#0d1018');
  bg.addColorStop(0.85, '#0a0e16');
  bg.addColorStop(1, '#060810');
  ctx.fillStyle = bg;
  ctx.beginPath();
  ctx.arc(CX, CY, RADIUS + 8, 0, Math.PI * 2);
  ctx.fill();

  ctx.strokeStyle = 'rgba(80, 160, 255, 0.25)';
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.arc(CX, CY, RADIUS, 0, Math.PI * 2);
  ctx.stroke();

  for (const frac of [0.25, 0.5, 0.75]) {
    ctx.strokeStyle = `rgba(80, 160, 255, ${0.06 + frac * 0.04})`;
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.arc(CX, CY, RADIUS * frac, 0, Math.PI * 2);
    ctx.stroke();
  }

  for (const dir of COMPASS) {
    const x2 = CX + Math.cos(dir.angle) * RADIUS;
    const y2 = CY + Math.sin(dir.angle) * RADIUS;
    ctx.strokeStyle = 'rgba(80, 160, 255, 0.08)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(CX, CY);
    ctx.lineTo(x2, y2);
    ctx.stroke();
  }

  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  for (const dir of COMPASS) {
    const labelR = RADIUS + 14;
    const lx = CX + Math.cos(dir.angle) * labelR;
    const ly = CY + Math.sin(dir.angle) * labelR;
    const isCardinal = dir.label.length === 1;
    ctx.fillStyle = isCardinal
      ? 'rgba(136, 204, 255, 0.6)'
      : 'rgba(136, 204, 255, 0.25)';
    ctx.font = isCardinal
      ? 'bold 11px Consolas, monospace'
      : '9px Consolas, monospace';
    ctx.fillText(dir.label, lx, ly);
  }

  ctx.fillStyle = 'rgba(80, 160, 255, 0.15)';
  ctx.beginPath();
  ctx.arc(CX, CY, 3, 0, Math.PI * 2);
  ctx.fill();

  const ARC_HALF = Math.PI / 12;
  const ARC_RADIUS = RADIUS - 4;
  if (actualSpeed > 0.02) {
    ctx.strokeStyle = 'rgba(255, 171, 0, 0.6)';
    ctx.lineWidth = 3;
    ctx.shadowColor = 'rgba(255, 171, 0, 0.3)';
    ctx.shadowBlur = 4;
    ctx.beginPath();
    ctx.arc(CX, CY, ARC_RADIUS, actualAngle - ARC_HALF, actualAngle + ARC_HALF);
    ctx.stroke();
    ctx.shadowBlur = 0;

    const ax = CX + Math.cos(actualAngle) * actualSpeed * RADIUS;
    const ay = CY + Math.sin(actualAngle) * actualSpeed * RADIUS;
    ctx.strokeStyle = 'rgba(255, 171, 0, 0.3)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(CX, CY);
    ctx.lineTo(ax, ay);
    ctx.stroke();

    ctx.fillStyle = '#ffab00';
    ctx.shadowColor = 'rgba(255, 171, 0, 0.5)';
    ctx.shadowBlur = 6;
    ctx.beginPath();
    ctx.arc(ax, ay, 5, 0, Math.PI * 2);
    ctx.fill();
    ctx.shadowBlur = 0;

    ctx.fillStyle = 'rgba(255, 171, 0, 0.6)';
    ctx.font = '8px Consolas, monospace';
    ctx.textAlign = 'left';
    ctx.fillText('ACT', ax + 8, ay + 3);
  }

  if (desiredThrottle > 0.02) {
    const dx = CX + Math.cos(desiredAngle) * desiredThrottle * RADIUS;
    const dy = CY + Math.sin(desiredAngle) * desiredThrottle * RADIUS;

    ctx.strokeStyle = 'rgba(0, 229, 255, 0.2)';
    ctx.lineWidth = 1;
    ctx.setLineDash([3, 3]);
    ctx.beginPath();
    ctx.moveTo(CX, CY);
    ctx.lineTo(dx, dy);
    ctx.stroke();
    ctx.setLineDash([]);

    ctx.fillStyle = '#00e5ff';
    ctx.shadowColor = 'rgba(0, 229, 255, 0.6)';
    ctx.shadowBlur = 8;
    ctx.beginPath();
    ctx.arc(dx, dy, 6, 0, Math.PI * 2);
    ctx.fill();
    ctx.shadowBlur = 0;

    ctx.fillStyle = 'rgba(255, 255, 255, 0.4)';
    ctx.beginPath();
    ctx.arc(dx, dy, 2, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = 'rgba(0, 229, 255, 0.6)';
    ctx.font = '8px Consolas, monospace';
    ctx.textAlign = 'left';
    ctx.fillText('DES', dx + 8, dy + 3);
  }

  if (focused) {
    ctx.strokeStyle = 'rgba(0, 229, 255, 0.2)';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(CX, CY, RADIUS + 4, 0, Math.PI * 2);
    ctx.stroke();
  }
}

export function NavBall(props: NavBallProps) {
  const {
    actualAngle,
    actualSpeed,
    desiredAngle: serverDesiredAngle,
    desiredThrottle: serverDesiredThrottle,
    locked,
    disabled,
    onSetDesired,
    onAllStop,
    onToggleLock,
  } = props;

  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [focused, setFocused] = useState(false);
  const dragging = useRef(false);
  const localAngle = useRef(serverDesiredAngle);
  const localThrottle = useRef(serverDesiredThrottle);
  const keyHeldSince = useRef<Record<string, number>>({});
  const animFrame = useRef<number>(0);
  const sReversed = useRef(false);
  const eHandled = useRef(false);

  useEffect(() => {
    localAngle.current = serverDesiredAngle;
    localThrottle.current = serverDesiredThrottle;
  }, [serverDesiredAngle, serverDesiredThrottle]);

  const mouseToAngleThrottle = useCallback(
    (e: MouseEvent | React.MouseEvent) => {
      const canvas = canvasRef.current;
      if (!canvas) return { angle: 0, throttle: 0 };
      const rect = canvas.getBoundingClientRect();
      const px = e.clientX - rect.left - CX;
      const py = e.clientY - rect.top - CY;
      const dist = Math.min(Math.hypot(px, py) / RADIUS, 1);
      const angle = Math.atan2(py, px);
      return { angle, throttle: dist };
    },
    [],
  );

  const sendDesiredRaw = useCallback(() => {
    onSetDesired(localAngle.current, localThrottle.current);
  }, [onSetDesired]);

  const sendDesired = useDebouncedCallback(sendDesiredRaw, HELM_DEBOUNCE_MS);

  const handleMouseDown = useCallback(
    (e: React.MouseEvent) => {
      if (disabled) return;
      if (!focused) {
        setFocused(true);
        e.preventDefault();
        return;
      }
      if (!locked) {
        dragging.current = true;
        const { angle, throttle } = mouseToAngleThrottle(e);
        localAngle.current = angle;
        localThrottle.current = throttle;
        sendDesired();
      }
      e.preventDefault();
    },
    [focused, locked, disabled, mouseToAngleThrottle, sendDesired],
  );

  useEffect(() => {
    const handleMove = (e: MouseEvent) => {
      if (!dragging.current || locked) return;
      const { angle, throttle } = mouseToAngleThrottle(e);
      localAngle.current = angle;
      localThrottle.current = throttle;
      sendDesired();
    };
    const handleUp = () => {
      dragging.current = false;
    };
    window.addEventListener('mousemove', handleMove);
    window.addEventListener('mouseup', handleUp);
    return () => {
      window.removeEventListener('mousemove', handleMove);
      window.removeEventListener('mouseup', handleUp);
    };
  }, [locked, mouseToAngleThrottle, sendDesired]);

  useEffect(() => {
    const handleDown = (e: MouseEvent) => {
      const canvas = canvasRef.current;
      if (e.target !== canvas && focused) {
        setFocused(false);
      }
    };
    document.addEventListener('mousedown', handleDown);
    return () => document.removeEventListener('mousedown', handleDown);
  }, [focused]);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (!focused) return;
      const key = e.key.toLowerCase();
      if (!(key in keyHeldSince.current)) {
        keyHeldSince.current[key] = performance.now();
      }
      e.preventDefault();
    };
    const handleKeyUp = (e: KeyboardEvent) => {
      delete keyHeldSince.current[e.key.toLowerCase()];
    };
    document.addEventListener('keydown', handleKeyDown);
    document.addEventListener('keyup', handleKeyUp);
    return () => {
      document.removeEventListener('keydown', handleKeyDown);
      document.removeEventListener('keyup', handleKeyUp);
    };
  }, [focused]);

  useEffect(() => {
    function keyRamp(key: string): number {
      if (!(key in keyHeldSince.current)) return 0;
      const held = performance.now() - keyHeldSince.current[key];
      const t = Math.min(held / WASD_RAMP_TIME, 1);
      return t ** WASD_EXPONENT;
    }

    function processKeys() {
      if (!focused || disabled) return;
      let changed = false;

      if ('e' in keyHeldSince.current && !eHandled.current) {
        onToggleLock();
        eHandled.current = true;
      }
      if (!('e' in keyHeldSince.current)) eHandled.current = false;

      if ('q' in keyHeldSince.current || ' ' in keyHeldSince.current) {
        onAllStop();
        localThrottle.current = 0;
        return;
      }

      if (locked) return;

      if ('a' in keyHeldSince.current) {
        localAngle.current -= keyRamp('a') * YAW_MAX_RATE;
        if (localThrottle.current < 0.01) localThrottle.current = 0.05;
        changed = true;
      }
      if ('d' in keyHeldSince.current) {
        localAngle.current += keyRamp('d') * YAW_MAX_RATE;
        if (localThrottle.current < 0.01) localThrottle.current = 0.05;
        changed = true;
      }
      if ('w' in keyHeldSince.current) {
        localThrottle.current = Math.min(
          1,
          localThrottle.current + keyRamp('w') * WASD_MAX_RATE,
        );
        changed = true;
      }
      if ('s' in keyHeldSince.current) {
        const ramp = keyRamp('s');
        if (sReversed.current) {
          localThrottle.current = Math.min(
            1,
            localThrottle.current + ramp * WASD_MAX_RATE,
          );
        } else if (localThrottle.current < 0.01) {
          localAngle.current += Math.PI;
          sReversed.current = true;
          localThrottle.current = ramp * WASD_MAX_RATE;
        } else {
          localThrottle.current = Math.max(
            0,
            localThrottle.current - ramp * WASD_MAX_RATE,
          );
        }
        changed = true;
      } else {
        sReversed.current = false;
      }

      if (changed) {
        sendDesired();
      }
    }

    function render() {
      processKeys();
      const ctx = canvasRef.current?.getContext('2d');
      if (ctx) {
        drawBall(
          ctx,
          actualAngle,
          actualSpeed,
          localAngle.current,
          localThrottle.current,
          focused,
        );
      }
      animFrame.current = requestAnimationFrame(render);
    }

    animFrame.current = requestAnimationFrame(render);
    return () => cancelAnimationFrame(animFrame.current);
  }, [
    focused,
    locked,
    disabled,
    actualAngle,
    actualSpeed,
    onAllStop,
    onToggleLock,
    sendDesired,
  ]);

  return (
    <div className="HelmConsole__navball-container">
      <div className="HelmConsole__navball-label">Navigation</div>
      <div className="HelmConsole__navball-row">
        <div className="HelmConsole__navball-wrapper">
          <canvas
            ref={canvasRef}
            className={
              'HelmConsole__navball-canvas' +
              (focused ? ' HelmConsole__navball-canvas--focused' : '')
            }
            width={240}
            height={240}
            onMouseDown={handleMouseDown}
          />
          <button
            className="HelmConsole__navball-btn HelmConsole__navball-btn--stop"
            onClick={(e) => {
              e.stopPropagation();
              onAllStop();
            }}
            title="All Stop (Q)"
          >
            <span className="HelmConsole__navball-btn-icon">&#x25A0;</span>
            <span className="HelmConsole__navball-btn-key">Q</span>
          </button>
          <button
            className={
              'HelmConsole__navball-btn HelmConsole__navball-btn--lock' +
              (locked ? ' HelmConsole__navball-btn--active' : '')
            }
            onClick={(e) => {
              e.stopPropagation();
              onToggleLock();
            }}
            title="Station Keeping (E)"
          >
            <span className="HelmConsole__navball-btn-icon">&#x2693;</span>
            <span className="HelmConsole__navball-btn-key">E</span>
          </button>
        </div>
        <ThrottleBar
          desired={localThrottle.current}
          actual={actualSpeed}
          locked={locked}
          disabled={disabled}
          onSetThrottle={(t) => {
            localThrottle.current = t;
            sendDesired();
          }}
        />
      </div>
      <div className="HelmConsole__readout">
        <div className="HelmConsole__readout-item">
          <span className="HelmConsole__readout-label">SPD</span>
          <span className="HelmConsole__readout-value">
            {actualSpeed > 0.01
              ? `${(actualSpeed * 100).toFixed(0)}%`
              : '0.0'}
          </span>
        </div>
        <div className="HelmConsole__readout-item">
          <span className="HelmConsole__readout-label">HDG</span>
          <span className="HelmConsole__readout-value">
            {actualSpeed > 0.02
              ? String(
                  Math.round(
                    ((-actualAngle * 180) / Math.PI + 90 + 360) % 360,
                  ),
                ).padStart(3, '0')
              : '---'}
          </span>
        </div>
      </div>
      <div className="HelmConsole__focus-hint">
        {focused ? 'A/D yaw \u2022 W/S throttle \u2022 Q stop \u2022 E lock' : 'Click ball for WASD control'}
      </div>
    </div>
  );
}

type ThrottleBarProps = {
  desired: number;
  actual: number;
  locked: boolean;
  disabled: boolean;
  onSetThrottle: (t: number) => void;
};

function ThrottleBar(props: ThrottleBarProps) {
  const { desired, actual, locked, disabled, onSetThrottle } = props;
  const trackRef = useRef<HTMLDivElement>(null);
  const dragging = useRef(false);

  const throttleFromMouse = useCallback(
    (e: MouseEvent | React.MouseEvent) => {
      const track = trackRef.current;
      if (!track) return 0;
      const rect = track.getBoundingClientRect();
      const py = e.clientY - rect.top;
      return Math.max(0, Math.min(1, 1 - py / rect.height));
    },
    [],
  );

  useEffect(() => {
    const handleMove = (e: MouseEvent) => {
      if (!dragging.current || locked || disabled) return;
      onSetThrottle(throttleFromMouse(e));
    };
    const handleUp = () => {
      dragging.current = false;
    };
    window.addEventListener('mousemove', handleMove);
    window.addEventListener('mouseup', handleUp);
    return () => {
      window.removeEventListener('mousemove', handleMove);
      window.removeEventListener('mouseup', handleUp);
    };
  }, [locked, disabled, throttleFromMouse, onSetThrottle]);

  return (
    <div className="HelmConsole__throttle">
      <div
        ref={trackRef}
        className="HelmConsole__throttle-track"
        onMouseDown={(e) => {
          if (locked || disabled) return;
          dragging.current = true;
          onSetThrottle(throttleFromMouse(e));
          e.preventDefault();
          e.stopPropagation();
        }}
      >
        <div
          className="HelmConsole__throttle-fill"
          style={{ height: `${desired * 100}%` }}
        />
        <div
          className="HelmConsole__throttle-marker"
          style={{ bottom: `${desired * 100}%` }}
        />
        <div
          className="HelmConsole__throttle-actual"
          style={{ bottom: `${actual * 100}%` }}
        />
        <div className="HelmConsole__throttle-ticks">
          <div
            className="HelmConsole__throttle-tick"
            style={{ bottom: '25%' }}
          />
          <div
            className="HelmConsole__throttle-tick"
            style={{ bottom: '50%' }}
          />
          <div
            className="HelmConsole__throttle-tick"
            style={{ bottom: '75%' }}
          />
        </div>
      </div>
      <div className="HelmConsole__throttle-key-hints">
        <span className="HelmConsole__throttle-key-hint">W +</span>
        <span className="HelmConsole__throttle-key-hint">S -</span>
      </div>
    </div>
  );
}
