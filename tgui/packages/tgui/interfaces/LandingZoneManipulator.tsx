// THIS IS A NOVA SECTOR UI FILE
import { useState } from 'react';
import {
  Box,
  Button,
  Dropdown,
  Input,
  LabeledList,
  NoticeBox,
  NumberInput,
  Section,
  Stack,
  Table,
  Tabs,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

import { useBackend } from '../backend';
import { Window } from '../layouts';

type FactionOption = {
  id: string;
  name: string;
};

type ZoneEntry = {
  ref: string;
  name: string;
  width: number;
  height: number;
  x: number;
  y: number;
  z: number;
  faction: string;
  exit_direction: number;
  occupied: BooleanLike;
  occupant_name: string | null;
  managed: BooleanLike;
  controller_ref: string | null;
};

type CornerEntry = {
  ref: string;
  x: number;
  y: number;
  z: number;
};

type ControllerEntry = {
  ref: string;
  name: string;
  label: string;
  type: string;
  x: number;
  y: number;
  z: number;
  faction: string;
  exit_direction: number;
  corners: number;
  corner_list: CornerEntry[];
  active: BooleanLike;
  invalid_reason: string | null;
  width: number;
  height: number;
  powered: BooleanLike;
  force_power: BooleanLike;
  occupied: BooleanLike;
  occupant_name: string | null;
  dock_policy: string;
  zone_ref: string | null;
};

type Data = {
  overmap_factions: FactionOption[];
  cap: number;
  zones: ZoneEntry[];
  controllers: ControllerEntry[];
};

const DIR_NONE = 0;
const DIR_NORTH = 1;
const DIR_SOUTH = 2;
const DIR_EAST = 4;
const DIR_WEST = 8;

const EXIT_OPTIONS = [
  { value: DIR_NONE, label: 'None' },
  { value: DIR_NORTH, label: 'North' },
  { value: DIR_SOUTH, label: 'South' },
  { value: DIR_EAST, label: 'East' },
  { value: DIR_WEST, label: 'West' },
];

const CONSOLE_TYPES = [
  { value: 'open', label: 'Open' },
  { value: 'nanotrasen', label: 'Nanotrasen' },
  { value: 'programmable', label: 'Programmable' },
];

const buildFactionOptions = (factions: FactionOption[] | undefined) => [
  { displayText: 'Open (any vessel)', value: 'open' },
  ...(factions || []).map((faction) => ({
    displayText: faction.name,
    value: faction.id,
  })),
];

const factionLabel = (factionId: string, options: { value: string; displayText: string }[]) => {
  const normalized = factionId || 'open';
  const match = options.find((option) => option.value === normalized);
  return match ? match.displayText : 'Open (any vessel)';
};

const exitLabel = (dir: number) =>
  EXIT_OPTIONS.find((option) => option.value === dir)?.label || 'None';

export const LandingZoneManipulator = () => {
  const [tab, setTab] = useState(1);

  return (
    <Window
      title="Landing Zone Manipulator"
      width={960}
      height={640}
      theme="admin"
    >
      <Window.Content scrollable>
        <Tabs>
          <Tabs.Tab selected={tab === 1} onClick={() => setTab(1)}>
            Zones
          </Tabs.Tab>
          <Tabs.Tab selected={tab === 2} onClick={() => setTab(2)}>
            Controllers
          </Tabs.Tab>
          <Tabs.Tab selected={tab === 3} onClick={() => setTab(3)}>
            Create
          </Tabs.Tab>
        </Tabs>
        {tab === 1 && <ZonesTab />}
        {tab === 2 && <ControllersTab />}
        {tab === 3 && <CreateTab />}
      </Window.Content>
    </Window>
  );
};

const ZonesTab = () => {
  const { act, data } = useBackend<Data>();
  const zones = data.zones || [];
  const factionOptions = buildFactionOptions(data.overmap_factions);

  return (
    <Section title={`Active Zones (${zones.length})`}>
      {!zones.length && <NoticeBox>No landing zones registered.</NoticeBox>}
      <Table>
        {zones.map((zone) => (
          <Table.Row key={zone.ref}>
            <Table.Cell>
              <Button
                content="JMP"
                onClick={() => act('jump_to', { ref: zone.ref })}
              />
            </Table.Cell>
            <Table.Cell>
              <Input
                fluid
                value={zone.name}
                onEnter={(value) =>
                  act('set_zone_name', { ref: zone.ref, name: value })
                }
              />
            </Table.Cell>
            <Table.Cell>
              {zone.width}&times;{zone.height}
            </Table.Cell>
            <Table.Cell>
              ({zone.x}, {zone.y}, z{zone.z})
            </Table.Cell>
            <Table.Cell>
              <Dropdown
                selected={factionLabel(zone.faction, factionOptions)}
                options={factionOptions}
                onSelected={(value) =>
                  act('set_zone_faction', { ref: zone.ref, faction: value })
                }
              />
            </Table.Cell>
            <Table.Cell>
              <Dropdown
                selected={exitLabel(zone.exit_direction)}
                options={EXIT_OPTIONS.map((option) => ({
                  displayText: option.label,
                  value: String(option.value),
                }))}
                onSelected={(value) =>
                  act('set_zone_exit', {
                    ref: zone.ref,
                    dir: Number(value),
                  })
                }
              />
            </Table.Cell>
            <Table.Cell>
              {zone.occupied ? zone.occupant_name || 'Occupied' : 'Clear'}
            </Table.Cell>
            <Table.Cell>
              {zone.managed ? 'Managed' : 'Landmark'}
            </Table.Cell>
            <Table.Cell>
              <Button.Confirm
                content="Delete"
                color="bad"
                disabled={!!zone.managed}
                onClick={() => act('delete_zone', { ref: zone.ref })}
              />
            </Table.Cell>
          </Table.Row>
        ))}
      </Table>
    </Section>
  );
};

const ControllersTab = () => {
  const { act, data } = useBackend<Data>();
  const controllers = data.controllers || [];
  const factionOptions = buildFactionOptions(data.overmap_factions);

  return (
    <Section title={`Controllers (${controllers.length})`}>
      {!controllers.length && (
        <NoticeBox>No landing zone controllers found.</NoticeBox>
      )}
      {controllers.map((console) => (
        <Section
          key={console.ref}
          title={`${console.label || console.name} (${console.corners}/4)`}
          buttons={
            <>
              <Button
                content="JMP"
                onClick={() => act('jump_to', { ref: console.ref })}
              />
              {!!console.zone_ref && (
                <Button
                  content="JMP Zone"
                  onClick={() => act('jump_to', { ref: console.zone_ref })}
                />
              )}
            </>
          }
        >
          <LabeledList>
            <LabeledList.Item label="Status">
              {console.active
                ? `Active ${console.width}×${console.height}`
                : `Inactive: ${console.invalid_reason || 'unknown'}`}
            </LabeledList.Item>
            <LabeledList.Item label="Power">
              {console.powered ? 'Powered' : 'Unpowered'}
              {!!console.force_power && ' (force-on)'}
            </LabeledList.Item>
            <LabeledList.Item label="Occupancy">
              {console.occupied
                ? console.occupant_name || 'Occupied'
                : 'Clear'}
            </LabeledList.Item>
            <LabeledList.Item label="Dock policy">
              {console.dock_policy}
            </LabeledList.Item>
            <LabeledList.Item label="Type">{console.type}</LabeledList.Item>
            <LabeledList.Item label="Location">
              ({console.x}, {console.y}, z{console.z})
            </LabeledList.Item>
            <LabeledList.Item label="Zone name">
              <Input
                fluid
                value={console.label}
                onEnter={(value) =>
                  act('set_controller_name', {
                    ref: console.ref,
                    name: value,
                  })
                }
              />
            </LabeledList.Item>
            <LabeledList.Item label="Faction">
              <Dropdown
                selected={factionLabel(console.faction, factionOptions)}
                options={factionOptions}
                onSelected={(value) =>
                  act('set_controller_faction', {
                    ref: console.ref,
                    faction: value,
                  })
                }
              />
            </LabeledList.Item>
            <LabeledList.Item label="Exit">
              <Dropdown
                selected={exitLabel(console.exit_direction)}
                options={EXIT_OPTIONS.map((option) => ({
                  displayText: option.label,
                  value: String(option.value),
                }))}
                onSelected={(value) =>
                  act('set_controller_exit', {
                    ref: console.ref,
                    dir: Number(value),
                  })
                }
              />
            </LabeledList.Item>
            <LabeledList.Item label="Corners">
              {(console.corner_list || []).map((corner, index) => (
                <Button
                  key={corner.ref}
                  content={`#${index + 1} (${corner.x},${corner.y})`}
                  onClick={() => act('jump_to', { ref: corner.ref })}
                />
              ))}
              {!console.corner_list?.length && 'None'}
            </LabeledList.Item>
          </LabeledList>
          <Stack mt={1}>
            <Stack.Item>
              <Button
                icon="bolt"
                color={console.force_power ? 'good' : undefined}
                onClick={() =>
                  act('toggle_force_power', { ref: console.ref })
                }
              >
                {console.force_power ? 'Force Power On' : 'Force Power'}
              </Button>
            </Stack.Item>
            <Stack.Item>
              <Button
                icon="rotate"
                onClick={() =>
                  act('validate_controller', { ref: console.ref })
                }
              >
                Re-validate
              </Button>
            </Stack.Item>
            <Stack.Item>
              <Button
                icon="link"
                onClick={() =>
                  act('link_marked_corner', { ref: console.ref })
                }
              >
                Link Marked Corner
              </Button>
            </Stack.Item>
            <Stack.Item>
              <Button.Confirm
                icon="xmark"
                color="bad"
                disabled={!console.corners}
                onClick={() =>
                  act('clear_controller_corners', { ref: console.ref })
                }
              >
                Clear Corners
              </Button.Confirm>
            </Stack.Item>
          </Stack>
        </Section>
      ))}
    </Section>
  );
};

const CreateTab = () => {
  const { act, data } = useBackend<Data>();
  const cap = data.cap || 40;
  const factionOptions = buildFactionOptions(data.overmap_factions);
  const [name, setName] = useState('Admin Landing Zone');
  const [width, setWidth] = useState(20);
  const [height, setHeight] = useState(20);
  const [faction, setFaction] = useState('open');
  const [exitDirection, setExitDirection] = useState(DIR_NORTH);
  const [consoleType, setConsoleType] = useState('open');

  const sharedParams = {
    name,
    faction,
    exit_direction: exitDirection,
    console_type: consoleType,
  };

  return (
    <Stack fill vertical>
      <Stack.Item>
        <Section title="Spawn Settings">
          <LabeledList>
            <LabeledList.Item label="Zone name">
              <Input fluid value={name} onChange={setName} />
            </LabeledList.Item>
            <LabeledList.Item label="Faction">
              <Dropdown
                selected={factionLabel(faction, factionOptions)}
                options={factionOptions}
                onSelected={setFaction}
              />
            </LabeledList.Item>
            <LabeledList.Item label="Exit">
              <Dropdown
                selected={exitLabel(exitDirection)}
                options={EXIT_OPTIONS.map((option) => ({
                  displayText: option.label,
                  value: String(option.value),
                }))}
                onSelected={(value) => setExitDirection(Number(value))}
              />
            </LabeledList.Item>
            <LabeledList.Item label="Console">
              <Dropdown
                selected={
                  CONSOLE_TYPES.find((entry) => entry.value === consoleType)
                    ?.label || 'Open'
                }
                options={CONSOLE_TYPES.map((entry) => ({
                  displayText: entry.label,
                  value: entry.value,
                }))}
                onSelected={setConsoleType}
              />
            </LabeledList.Item>
            <LabeledList.Item label="Width">
              <NumberInput
                minValue={2}
                maxValue={cap}
                step={1}
                value={width}
                onChange={setWidth}
              />
            </LabeledList.Item>
            <LabeledList.Item label="Height">
              <NumberInput
                minValue={2}
                maxValue={cap}
                step={1}
                value={height}
                onChange={setHeight}
              />
            </LabeledList.Item>
          </LabeledList>
          <Box color="label" italic mt={1}>
            Linked spawn uses your current turf as the south-west corner.
            Controllers are force-powered so they activate without APC power.
          </Box>
        </Section>
      </Stack.Item>
      <Stack.Item>
        <Section title="Actions">
          <Button
            icon="vector-square"
            color="good"
            onClick={() =>
              act('spawn_linked_zone', {
                ...sharedParams,
                width,
                height,
              })
            }
          >
            Spawn Linked Zone Here
          </Button>
          <Button
            icon="box"
            ml={1}
            onClick={() => act('spawn_kit', sharedParams)}
          >
            Spawn Unlinked Kit Here
          </Button>
        </Section>
      </Stack.Item>
      <Stack.Item>
        <NoticeBox info>
          Unlinked kit: console + 4 corners at your feet (mark console, VV-link
          corners, or use Controllers → Link Marked Corner). Linked zone places
          and wires a rectangle immediately.
        </NoticeBox>
      </Stack.Item>
    </Stack>
  );
};
