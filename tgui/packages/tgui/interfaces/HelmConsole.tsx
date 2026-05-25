// THIS IS A NOVA SECTOR UI FILE
import { useState } from 'react';
import { ByondUi, NoticeBox, ProgressBar } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

import { useBackend } from '../backend';
import { Window } from '../layouts';
import { NavBall } from './HelmConsole/NavBall';
import './HelmConsole/helm-console.scss';

type ShipInfo = {
  name: string;
  class: string;
  integrity: number;
  sensor_range: number;
  ref: string;
  mass?: number;
  est_thrust?: number;
};

type OtherShip = {
  name: string;
  integrity: number;
  ref: string;
  bearing?: number;
  distance?: number;
  adjacent?: BooleanLike;
  type?: 'level' | 'dynamic' | 'ship' | 'event' | 'unknown';
};

type EngineInfo = {
  name: string;
  fuel: number;
  maxFuel: number;
  enabled: BooleanLike;
  ref: string;
};

type Data = {
  canFly: BooleanLike;
  isViewer: BooleanLike;
  mapRef: string;
  shipInfo: ShipInfo;
  otherInfo: OtherShip[];
  engineInfo?: EngineInfo[];
  speed?: number;
  maxSpeed?: number;
  heading?: number;
  actual_angle?: number;
  actual_speed?: number;
  desired_angle?: number;
  desired_throttle?: number;
  station_keeping?: BooleanLike;
  x: number;
  y: number;
  state?: 'idle' | 'flying' | 'docking' | 'undocking';
  stopped?: BooleanLike;
  docked?: BooleanLike;
  scanReady?: BooleanLike;
  consoleControl?: BooleanLike;
};

export const HelmConsole = () => {
  const { act, data } = useBackend<Data>();
  const { canFly, isViewer, mapRef } = data;
  const [activeTab, setActiveTab] = useState<'status' | 'engines' | 'radar'>(
    'status',
  );

  return (
    <Window width={900} height={720}>
      <Window.Content className="HelmConsole">
        <div className="HelmConsole__viewscreen">
          {mapRef ? (
            <ByondUi
              height="100%"
              width="100%"
              params={{ id: mapRef, type: 'map' }}
            />
          ) : (
            <NoticeBox>
              Helm not bound to any overmap object. Move it to a shuttle, or
              set its target via VV.
            </NoticeBox>
          )}
        </div>
        <div className="HelmConsole__console">
          {!!canFly && !isViewer && (
            <NavBall
              actualAngle={data.actual_angle ?? 0}
              actualSpeed={data.actual_speed ?? 0}
              desiredAngle={data.desired_angle ?? 0}
              desiredThrottle={data.desired_throttle ?? 0}
              locked={!!data.station_keeping}
              disabled={data.state !== 'flying'}
              onSetDesired={(angle, throttle) =>
                act('set_desired', { angle, throttle })
              }
              onAllStop={() => act('all_stop')}
              onToggleLock={() => act('toggle_lock')}
            />
          )}
          <div className="HelmConsole__panel">
            <div className="HelmConsole__tabs">
              <button
                className={
                  'HelmConsole__tab' +
                  (activeTab === 'status' ? ' HelmConsole__tab--active' : '')
                }
                onClick={() => setActiveTab('status')}
              >
                Status
              </button>
              <button
                className={
                  'HelmConsole__tab' +
                  (activeTab === 'engines' ? ' HelmConsole__tab--active' : '')
                }
                onClick={() => setActiveTab('engines')}
              >
                Engines
              </button>
              <button
                className={
                  'HelmConsole__tab' +
                  (activeTab === 'radar' ? ' HelmConsole__tab--active' : '')
                }
                onClick={() => setActiveTab('radar')}
              >
                Radar
              </button>
            </div>
            <div className="HelmConsole__tab-content">
              {activeTab === 'status' && <StatusTab />}
              {activeTab === 'engines' && <EnginesTab />}
              {activeTab === 'radar' && <RadarTab />}
            </div>
          </div>
        </div>
      </Window.Content>
    </Window>
  );
};

const StatusTab = () => {
  const { act, data } = useBackend<Data>();
  const { shipInfo, state, docked, x, y } = data;
  if (!shipInfo) return null;

  const stateColor: Record<string, string> = {
    idle: '#8cf',
    flying: '#3dbc6a',
    docking: '#e8b830',
    undocking: '#e8b830',
  };

  return (
    <>
      <div className="HelmPanel__section">
        <div className="HelmPanel__section-title">Ship Info</div>
        <div className="HelmPanel__row">
          <span className="HelmPanel__label">Name</span>
          <span className="HelmPanel__value">{shipInfo.name}</span>
        </div>
        <div className="HelmPanel__row">
          <span className="HelmPanel__label">Class</span>
          <span className="HelmPanel__value">{shipInfo.class}</span>
        </div>
        <div className="HelmPanel__row">
          <span className="HelmPanel__label">Integrity</span>
          <span className="HelmPanel__value">
            <ProgressBar
              ranges={{
                good: [51, 100],
                average: [26, 50],
                bad: [0, 25],
              }}
              maxValue={100}
              value={shipInfo.integrity}
            >
              {Math.round(shipInfo.integrity)}%
            </ProgressBar>
          </span>
        </div>
        <div className="HelmPanel__row">
          <span className="HelmPanel__label">Sensor Range</span>
          <span className="HelmPanel__value">{shipInfo.sensor_range}</span>
        </div>
        {shipInfo.mass !== undefined && (
          <div className="HelmPanel__row">
            <span className="HelmPanel__label">Mass</span>
            <span className="HelmPanel__value">{shipInfo.mass} tonnes</span>
          </div>
        )}
        {shipInfo.est_thrust !== undefined && (
          <div className="HelmPanel__row">
            <span className="HelmPanel__label">Est. Thrust</span>
            <span className="HelmPanel__value">{shipInfo.est_thrust}</span>
          </div>
        )}
      </div>
      <div className="HelmPanel__section">
        <div className="HelmPanel__section-title">Flight</div>
        <div className="HelmPanel__row">
          <span className="HelmPanel__label">State</span>
          <span
            className="HelmPanel__value"
            style={{ color: stateColor[state ?? 'idle'] }}
          >
            {state ?? 'idle'}
          </span>
        </div>
        <div className="HelmPanel__row">
          <span className="HelmPanel__label">Position</span>
          <span className="HelmPanel__value">
            X{x} / Y{y}
          </span>
        </div>
      </div>
      {!!docked && state === 'idle' && (
        <div className="HelmPanel__section">
          <button
            className="HelmPanel__btn HelmPanel__btn--danger"
            style={{ width: '100%' }}
            onClick={() => act('undock')}
          >
            Undock
          </button>
        </div>
      )}
    </>
  );
};

const EnginesTab = () => {
  const { act, data } = useBackend<Data>();
  const { isViewer, engineInfo = [] } = data;

  return (
    <div className="HelmPanel__section">
      <div className="HelmPanel__section-title">Engines</div>
      {engineInfo.length === 0 ? (
        <div className="HelmPanel__radar-empty">No engines connected.</div>
      ) : (
        engineInfo.map((engine) => (
          <div className="HelmPanel__engine-row" key={engine.ref}>
            <button
              className={
                'HelmPanel__engine-toggle' +
                (engine.enabled ? ' HelmPanel__engine-toggle--on' : '')
              }
              disabled={!!isViewer}
              onClick={() => act('toggle_engine', { engine: engine.ref })}
            >
              <span
                className={
                  'HelmPanel__engine-indicator' +
                  (engine.enabled ? ' HelmPanel__engine-indicator--on' : '')
                }
              />
              {engine.name}
            </button>
            <div className="HelmPanel__engine-fuel">
              {engine.maxFuel > 0 && (
                <div className="HelmPanel__bar">
                  <div
                    className={
                      'HelmPanel__bar-fill ' +
                      (engine.fuel / engine.maxFuel > 0.5
                        ? 'HelmPanel__bar-fill--good'
                        : engine.fuel / engine.maxFuel > 0.25
                          ? 'HelmPanel__bar-fill--average'
                          : 'HelmPanel__bar-fill--bad')
                    }
                    style={{
                      width: `${(engine.fuel / engine.maxFuel) * 100}%`,
                    }}
                  />
                  <div className="HelmPanel__bar-text">
                    {Math.round((engine.fuel / engine.maxFuel) * 100)}%
                  </div>
                </div>
              )}
            </div>
          </div>
        ))
      )}
      <button
        className="HelmPanel__btn"
        style={{ width: '100%', marginTop: '8px' }}
        disabled={!!isViewer}
        onClick={() => act('reload_engines')}
      >
        Refresh Engines
      </button>
    </div>
  );
};

const contactTypeLabel = (type?: string) => {
  switch (type) {
    case 'level':
      return 'POI';
    case 'dynamic':
      return 'SIG';
    case 'ship':
      return 'SHIP';
    case 'event':
      return 'HAZ';
    default:
      return '???';
  }
};

const RadarTab = () => {
  const { act, data } = useBackend<Data>();
  const { isViewer, otherInfo = [], state, stopped, scanReady } = data;
  const canDock = !isViewer && state === 'flying' && !!stopped && !data.docked;

  return (
    <div className="HelmPanel__section">
      <div
        className="HelmPanel__section-title"
        style={{ display: 'flex', justifyContent: 'space-between' }}
      >
        <span>Contacts</span>
        <button
          className="HelmPanel__btn"
          disabled={!!isViewer || !scanReady}
          onClick={() => act('scan')}
          style={{ fontSize: '10px', padding: '2px 8px' }}
        >
          {scanReady ? 'Scan' : 'Scanning...'}
        </button>
      </div>
      {otherInfo.length === 0 ? (
        <div className="HelmPanel__radar-empty">
          No contacts detected. Use Scan to sweep sensor range.
        </div>
      ) : (
        otherInfo.map((contact) => (
          <div className="HelmPanel__radar-item" key={contact.ref}>
            <div style={{ flex: 1 }}>
              <div className="HelmPanel__radar-name">
                <span
                  style={{
                    opacity: 0.6,
                    fontSize: '10px',
                    marginRight: '4px',
                  }}
                >
                  [{contactTypeLabel(contact.type)}]
                </span>
                {contact.name}
              </div>
              <div
                style={{ fontSize: '10px', opacity: 0.7, marginTop: '2px' }}
              >
                {contact.adjacent
                  ? 'Adjacent'
                  : `${String(contact.bearing ?? 0).padStart(3, '0')}° / ${contact.distance ?? '?'} tile${(contact.distance ?? 0) !== 1 ? 's' : ''}`}
              </div>
            </div>
            <div className="HelmPanel__radar-actions">
              {contact.adjacent && contact.type !== 'event' ? (
                <button
                  className="HelmPanel__btn"
                  disabled={!canDock}
                  onClick={() => act('dock', { target: contact.ref })}
                >
                  {contact.type === 'dynamic' ? 'Explore' : 'Dock'}
                </button>
              ) : null}
            </div>
          </div>
        ))
      )}
    </div>
  );
};
