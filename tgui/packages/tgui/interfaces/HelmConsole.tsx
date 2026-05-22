// THIS IS A NOVA SECTOR UI FILE
import {
  Box,
  Button,
  ByondUi,
  LabeledList,
  NoticeBox,
  ProgressBar,
  Section,
  Stack,
  Table,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

import { useBackend } from '../backend';
import { Window } from '../layouts';

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
  eta?: number;
  x: number;
  y: number;
  state?: 'idle' | 'flying' | 'docking' | 'undocking';
  stopped?: BooleanLike;
  docked?: BooleanLike;
};

const DIRECTIONS = {
  north: 1,
  south: 2,
  east: 4,
  west: 8,
  northeast: 1 + 4,
  northwest: 1 + 8,
  southeast: 2 + 4,
  southwest: 2 + 8,
};

export const HelmConsole = (props) => {
  const { data } = useBackend<Data>();
  const { canFly, isViewer, mapRef } = data;

  return (
    <Window width={870} height={708}>
      <Window.Content>
        <Stack fill>
          <Stack.Item width="380px">
            <Stack fill vertical>
              {!!canFly && !isViewer && (
                <Stack.Item>
                  <ShipControlPanel />
                </Stack.Item>
              )}
              {!!canFly && (
                <Stack.Item>
                  <VelocityPanel />
                </Stack.Item>
              )}
              {!!canFly && (
                <Stack.Item>
                  <EnginesPanel />
                </Stack.Item>
              )}
              <Stack.Item>
                <ShipInfoPanel />
              </Stack.Item>
              <Stack.Item grow>
                <RadarPanel />
              </Stack.Item>
            </Stack>
          </Stack.Item>
          <Stack.Item grow>
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
          </Stack.Item>
        </Stack>
      </Window.Content>
    </Window>
  );
};

const ShipInfoPanel = () => {
  const { act, data } = useBackend<Data>();
  const { isViewer, shipInfo } = data;
  if (!shipInfo) {
    return null;
  }
  return (
    <Section
      title={shipInfo.name || 'Ship Info'}
      buttons={
        <Button
          tooltip="Refresh ship binding"
          icon="sync"
          disabled={!!isViewer}
          onClick={() => act('reload_ship')}
        />
      }
    >
      <LabeledList>
        <LabeledList.Item label="Class">{shipInfo.class}</LabeledList.Item>
        <LabeledList.Item label="Integrity">
          <ProgressBar
            ranges={{
              good: [51, 100],
              average: [26, 50],
              bad: [0, 25],
            }}
            maxValue={100}
            value={shipInfo.integrity}
          />
        </LabeledList.Item>
        <LabeledList.Item label="Sensor Range">
          {shipInfo.sensor_range}
        </LabeledList.Item>
        {shipInfo.mass !== undefined && (
          <LabeledList.Item label="Mass">
            {shipInfo.mass} tonnes
          </LabeledList.Item>
        )}
      </LabeledList>
    </Section>
  );
};

const RadarPanel = () => {
  const { act, data } = useBackend<Data>();
  const { isViewer, otherInfo = [], state, stopped } = data;
  const canAct = !isViewer && state === 'flying' && stopped;
  return (
    <Section title="Radar" fill scrollable>
      {otherInfo.length === 0 ? (
        <Box color="label">Nothing on this tile.</Box>
      ) : (
        <Table>
          <Table.Row header>
            <Table.Cell>Name</Table.Cell>
            <Table.Cell>Integrity</Table.Cell>
            {!isViewer && <Table.Cell collapsing>Act</Table.Cell>}
          </Table.Row>
          {otherInfo.map((ship) => (
            <Table.Row key={ship.ref}>
              <Table.Cell>{ship.name}</Table.Cell>
              <Table.Cell>
                {ship.integrity > 0 && (
                  <ProgressBar
                    ranges={{
                      good: [51, 100],
                      average: [26, 50],
                      bad: [0, 25],
                    }}
                    maxValue={100}
                    value={ship.integrity}
                  />
                )}
              </Table.Cell>
              {!isViewer && (
                <Table.Cell collapsing>
                  <Button
                    tooltip="Dock here"
                    icon="circle"
                    disabled={!canAct}
                    onClick={() =>
                      act('act_overmap', { ship_to_act: ship.ref })
                    }
                  />
                </Table.Cell>
              )}
            </Table.Row>
          ))}
        </Table>
      )}
    </Section>
  );
};

const VelocityPanel = () => {
  const { data } = useBackend<Data>();
  const { speed, heading, x, y, eta } = data;
  return (
    <Section title="Velocity">
      <LabeledList>
        <LabeledList.Item label="Speed">
          <ProgressBar
            ranges={{
              good: [0, 4],
              average: [5, 6],
              bad: [7, Infinity],
            }}
            maxValue={10}
            value={speed ?? 0}
          >
            {Math.round((speed ?? 0) * 10) / 10} spM
          </ProgressBar>
        </LabeledList.Item>
        <LabeledList.Item label="Heading">{heading ?? 0}</LabeledList.Item>
        <LabeledList.Item label="Position">
          X{x} / Y{y}
        </LabeledList.Item>
        <LabeledList.Item label="Next">
          {eta && eta > 0 && eta < 10000 ? `${Math.round(eta / 10)}s` : 'N/A'}
        </LabeledList.Item>
      </LabeledList>
    </Section>
  );
};

const EnginesPanel = () => {
  const { act, data } = useBackend<Data>();
  const { isViewer, engineInfo = [] } = data;
  return (
    <Section
      title="Engines"
      buttons={
        <Button
          tooltip="Refresh engine bindings"
          icon="sync"
          disabled={!!isViewer}
          onClick={() => act('reload_engines')}
        />
      }
    >
      {engineInfo.length === 0 ? (
        <Box color="label">No engines connected.</Box>
      ) : (
        <Table>
          <Table.Row header>
            <Table.Cell>Engine</Table.Cell>
            <Table.Cell>Fuel</Table.Cell>
          </Table.Row>
          {engineInfo.map((engine) => (
            <Table.Row key={engine.ref}>
              <Table.Cell collapsing>
                <Button
                  content={engine.name}
                  color={engine.enabled ? 'good' : undefined}
                  icon={engine.enabled ? 'toggle-on' : 'toggle-off'}
                  disabled={!!isViewer}
                  tooltip="Toggle engine"
                  onClick={() =>
                    act('toggle_engine', { engine: engine.ref })
                  }
                />
              </Table.Cell>
              <Table.Cell>
                {engine.maxFuel > 0 && (
                  <ProgressBar
                    ranges={{
                      good: [50, Infinity],
                      average: [25, 50],
                      bad: [-Infinity, 25],
                    }}
                    maxValue={engine.maxFuel}
                    minValue={0}
                    value={engine.fuel}
                  >
                    {Math.round((engine.fuel / engine.maxFuel) * 100)}%
                  </ProgressBar>
                )}
              </Table.Cell>
            </Table.Row>
          ))}
        </Table>
      )}
    </Section>
  );
};

const ShipControlPanel = () => {
  const { act, data } = useBackend<Data>();
  const flyable = data.state === 'flying';
  const idle = data.state === 'idle';
  return (
    <Section
      title="Navigation"
      buttons={
        <Button
          tooltip="Undock"
          icon="sign-out-alt"
          disabled={!idle}
          onClick={() => act('undock')}
        />
      }
    >
      <Table>
        <Table.Row>
          <Table.Cell>
            <Button
              icon="arrow-left"
              iconRotation={45}
              disabled={!flyable}
              onClick={() =>
                act('change_heading', { dir: DIRECTIONS.northwest })
              }
            />
          </Table.Cell>
          <Table.Cell>
            <Button
              icon="arrow-up"
              disabled={!flyable}
              onClick={() => act('change_heading', { dir: DIRECTIONS.north })}
            />
          </Table.Cell>
          <Table.Cell>
            <Button
              icon="arrow-right"
              iconRotation={-45}
              disabled={!flyable}
              onClick={() =>
                act('change_heading', { dir: DIRECTIONS.northeast })
              }
            />
          </Table.Cell>
        </Table.Row>
        <Table.Row>
          <Table.Cell>
            <Button
              icon="arrow-left"
              disabled={!flyable}
              onClick={() => act('change_heading', { dir: DIRECTIONS.west })}
            />
          </Table.Cell>
          <Table.Cell>
            <Button
              tooltip="Stop"
              icon="circle"
              disabled={!!data.stopped || !flyable}
              onClick={() => act('stop')}
            />
          </Table.Cell>
          <Table.Cell>
            <Button
              icon="arrow-right"
              disabled={!flyable}
              onClick={() => act('change_heading', { dir: DIRECTIONS.east })}
            />
          </Table.Cell>
        </Table.Row>
        <Table.Row>
          <Table.Cell>
            <Button
              icon="arrow-left"
              iconRotation={-45}
              disabled={!flyable}
              onClick={() =>
                act('change_heading', { dir: DIRECTIONS.southwest })
              }
            />
          </Table.Cell>
          <Table.Cell>
            <Button
              icon="arrow-down"
              disabled={!flyable}
              onClick={() => act('change_heading', { dir: DIRECTIONS.south })}
            />
          </Table.Cell>
          <Table.Cell>
            <Button
              icon="arrow-right"
              iconRotation={45}
              disabled={!flyable}
              onClick={() =>
                act('change_heading', { dir: DIRECTIONS.southeast })
              }
            />
          </Table.Cell>
        </Table.Row>
      </Table>
    </Section>
  );
};
