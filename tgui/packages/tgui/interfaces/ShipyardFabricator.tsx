// THIS IS A NOVA SECTOR UI FILE
import {
  Box,
  Button,
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

type SupplyEntry = {
  name: string;
  required: number;
  available: number;
};

type Fault = {
  x: number;
  y: number;
  phase: number;
  reason: string;
};

type Data = {
  state: 'idle' | 'building' | 'paused' | 'fault' | 'complete';
  pausedReason: string | null;
  planName: string | null;
  planWidth: number;
  planHeight: number;
  operation: number;
  operationTotal: number;
  phase: number;
  skipped: string[];
  faults: Fault[];
  siloLinked: BooleanLike;
  siloOnHold: BooleanLike;
  rpedDocked: BooleanLike;
  diskLoaded: BooleanLike;
  blueprintsLoaded: BooleanLike;
  zoneLinked: BooleanLike;
  zoneActive: BooleanLike;
  zoneName: string | null;
  zoneWidth: number;
  zoneHeight: number;
  zoneOccupied: BooleanLike;
  materialMultiplier: number;
  placementDelay: number;
  maxPrintRange: number;
  materials: SupplyEntry[];
  parts: SupplyEntry[];
};

const PHASE_NAMES = [
  'Idle',
  'Frame rods',
  'Hull plating',
  'Frames and girders',
  'Walls and windows',
  'Pipes and wiring',
  'Machines and airlocks',
  'Commissioning',
];

export const ShipyardFabricator = () => {
  const { act, data } = useBackend<Data>();
  const running = data.state === 'building';
  const resumable = data.state === 'paused' || data.state === 'fault';
  const canStart =
    !!data.diskLoaded &&
    !!data.rpedDocked &&
    !!data.siloLinked &&
    !data.siloOnHold &&
    !!data.zoneActive &&
    !data.zoneOccupied;

  return (
    <Window width={720} height={700}>
      <Window.Content scrollable>
        {data.pausedReason && (
          <NoticeBox danger={data.state === 'fault'}>{data.pausedReason}</NoticeBox>
        )}
        <Stack>
          <Stack.Item grow>
            <Section title="Build Control">
              <LabeledList>
                <LabeledList.Item label="State">{data.state}</LabeledList.Item>
                <LabeledList.Item label="Phase">
                  {PHASE_NAMES[data.phase] || `Phase ${data.phase}`}
                </LabeledList.Item>
                <LabeledList.Item label="Placement">
                  {(data.placementDelay / 10).toFixed(2)}s per operation
                </LabeledList.Item>
                <LabeledList.Item label="Material cost">
                  {Math.round(data.materialMultiplier * 100)}% of hand construction
                </LabeledList.Item>
                <LabeledList.Item label="Print range">
                  {data.maxPrintRange} tiles
                </LabeledList.Item>
              </LabeledList>
              <ProgressBar
                mt={1}
                value={data.operationTotal ? data.operation / data.operationTotal : 0}
              >
                {data.operation} / {data.operationTotal} operations
              </ProgressBar>
              <Box mt={1}>
                {!running && !resumable && (
                  <Button
                    icon="play"
                    color="good"
                    disabled={!canStart}
                    onClick={() => act('start')}
                  >
                    Start
                  </Button>
                )}
                {running && (
                  <Button icon="pause" onClick={() => act('pause')}>
                    Pause
                  </Button>
                )}
                {resumable && (
                  <Button icon="play" color="good" onClick={() => act('resume')}>
                    Resume
                  </Button>
                )}
                <Button.Confirm
                  ml={1}
                  icon="stop"
                  color="bad"
                  disabled={data.state === 'idle'}
                  onClick={() => act('abort')}
                >
                  Abort
                </Button.Confirm>
              </Box>
            </Section>
          </Stack.Item>
          <Stack.Item grow>
            <Section title="Landing Zone">
              <LabeledList>
                <LabeledList.Item label="Controller">
                  {data.zoneLinked ? 'Linked' : 'Missing'}
                </LabeledList.Item>
                <LabeledList.Item label="Zone">
                  {data.zoneActive
                    ? `${data.zoneName} (${data.zoneWidth}×${data.zoneHeight})`
                    : 'Inactive'}
                </LabeledList.Item>
                <LabeledList.Item label="Occupancy">
                  {data.zoneOccupied ? 'Occupied' : 'Clear'}
                </LabeledList.Item>
                <LabeledList.Item label="Silo">
                  {!data.siloLinked
                    ? 'Unlinked'
                    : data.siloOnHold
                      ? 'On hold'
                      : 'Available'}
                </LabeledList.Item>
              </LabeledList>
            </Section>
          </Stack.Item>
        </Stack>

        <Section
          title="Blueprint"
          buttons={
            <Button
              icon="eject"
              disabled={!data.diskLoaded || running}
              onClick={() => act('eject_disk')}
            >
              Eject disk
            </Button>
          }
        >
          {data.planName ? (
            <LabeledList>
              <LabeledList.Item label="Design">{data.planName}</LabeledList.Item>
              <LabeledList.Item label="Footprint">
                {data.planWidth}×{data.planHeight}
              </LabeledList.Item>
              <LabeledList.Item label="Skipped map entries">
                {data.skipped.length}
              </LabeledList.Item>
            </LabeledList>
          ) : (
            <NoticeBox>Insert a ship blueprint disk.</NoticeBox>
          )}
        </Section>

        <SupplyTable title="Silo Materials (sheets)" entries={data.materials} />
        <SupplyTable title="RPED Boards and Parts" entries={data.parts} />

        <Section
          title="Docked RPED"
          buttons={
            <Button
              icon="eject"
              disabled={!data.rpedDocked || running}
              onClick={() => act('eject_rped')}
            >
              Eject
            </Button>
          }
        >
          {data.rpedDocked ? 'Parts inventory available.' : 'Dock an RPED.'}
        </Section>

        {!!data.faults.length && (
          <Section title="Located Faults">
            {data.faults.map((fault, index) => (
              <NoticeBox key={index} danger>
                ({fault.x}, {fault.y}) — phase {fault.phase}: {fault.reason}
              </NoticeBox>
            ))}
          </Section>
        )}

        {!!data.skipped.length && (
          <Section title="Manifest Skip Report">
            {data.skipped.map((entry, index) => (
              <Box key={index} color="label">
                {entry}
              </Box>
            ))}
          </Section>
        )}
      </Window.Content>
    </Window>
  );
};

const SupplyTable = (props: { title: string; entries: SupplyEntry[] }) => (
  <Section title={props.title}>
    {!props.entries.length ? (
      <Box color="label">No requirements loaded.</Box>
    ) : (
      <Table>
        <Table.Row header>
          <Table.Cell>Item</Table.Cell>
          <Table.Cell textAlign="right">Available</Table.Cell>
          <Table.Cell textAlign="right">Required</Table.Cell>
        </Table.Row>
        {props.entries.map((entry) => (
          <Table.Row key={entry.name}>
            <Table.Cell>{entry.name}</Table.Cell>
            <Table.Cell
              textAlign="right"
              color={entry.available >= entry.required ? 'good' : 'bad'}
            >
              {entry.available}
            </Table.Cell>
            <Table.Cell textAlign="right">{entry.required}</Table.Cell>
          </Table.Row>
        ))}
      </Table>
    )}
  </Section>
);

