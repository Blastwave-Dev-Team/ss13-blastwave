// THIS IS A NOVA SECTOR UI FILE
import {
  Box,
  Button,
  Icon,
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

type SkipCategory = 'ignored' | 'blacklisted' | 'unsupported';

const SKIP_CATEGORY_LABELS: Record<SkipCategory, string> = {
  unsupported: 'no construction route',
  blacklisted: 'refused',
  ignored: 'cosmetic',
};

type Data = {
  authenticated: BooleanLike;
  operatorName: string | null;
  state: 'idle' | 'building' | 'paused' | 'fault' | 'complete';
  pausedReason: string | null;
  planName: string | null;
  planWidth: number;
  planHeight: number;
  operation: number;
  operationTotal: number;
  phase: number;
  skipped: string[];
  skippedCounts: Partial<Record<SkipCategory, number>>;
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

const summarizeSkips = (
  counts: Partial<Record<SkipCategory, number>>,
): string => {
  const parts = (Object.keys(SKIP_CATEGORY_LABELS) as SkipCategory[])
    .filter((category) => !!counts[category])
    .map((category) => `${counts[category]} ${SKIP_CATEGORY_LABELS[category]}`);
  return parts.length
    ? `Not built: ${parts.join(', ')}.`
    : 'Every mapped entry has a construction route.';
};

const LoginView = () => {
  const { act } = useBackend<Data>();

  return (
    <Stack fill vertical>
      <Stack.Item grow />
      <Stack.Item align="center">
        <Icon name="industry" size={9} color="good" />
      </Stack.Item>
      <Stack.Item align="center">
        <Box color="good" fontSize="18px" bold>
          Nanotrasen ShipworksNET
        </Box>
      </Stack.Item>
      <Stack.Item align="center">
        <Box color="label" italic>
          Hull Fabrication Authority Terminal
        </Box>
      </Stack.Item>
      <Stack.Item align="center">
        <Box color="label" italic>
          Silo draws are billed to the logged-in operator.
        </Box>
      </Stack.Item>
      <Stack.Item grow />
      <Stack.Item>
        <NoticeBox align="right">
          You are not logged in.
          <Button ml={2} icon="lock-open" onClick={() => act('login')}>
            Login
          </Button>
        </NoticeBox>
      </Stack.Item>
    </Stack>
  );
};

export const ShipyardFabricator = () => {
  const { data } = useBackend<Data>();

  return (
    <Window width={720} height={700}>
      <Window.Content scrollable={!!data.authenticated}>
        {data.authenticated ? <FabricatorView /> : <LoginView />}
      </Window.Content>
    </Window>
  );
};

const FabricatorView = () => {
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
    <>
      {data.pausedReason && (
        <NoticeBox danger={data.state === 'fault'}>
          {data.pausedReason}
        </NoticeBox>
      )}
      <Stack>
        <Stack.Item grow>
          <Section title="Build Control">
            <LabeledList>
              <LabeledList.Item label="Operator">
                {data.operatorName || 'Unidentified'}
              </LabeledList.Item>
              <LabeledList.Item label="State">{data.state}</LabeledList.Item>
              <LabeledList.Item label="Phase">
                {PHASE_NAMES[data.phase] || `Phase ${data.phase}`}
              </LabeledList.Item>
              <LabeledList.Item label="Placement">
                {(data.placementDelay / 10).toFixed(2)}s per operation
              </LabeledList.Item>
              <LabeledList.Item label="Material cost">
                {Math.round(data.materialMultiplier * 100)}% of hand
                construction
              </LabeledList.Item>
              <LabeledList.Item label="Print range">
                {data.maxPrintRange} tiles
              </LabeledList.Item>
            </LabeledList>
            <ProgressBar
              mt={1}
              value={
                data.operationTotal ? data.operation / data.operationTotal : 0
              }
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
              <Button
                ml={1}
                icon="lock"
                disabled={running}
                onClick={() => act('logout')}
              >
                Logout
              </Button>
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
          <Box mb={1}>{summarizeSkips(data.skippedCounts)}</Box>
          {data.skipped.map((entry, index) => (
            <Box key={index} color="label">
              {entry}
            </Box>
          ))}
        </Section>
      )}
    </>
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
