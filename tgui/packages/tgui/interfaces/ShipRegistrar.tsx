// THIS IS A NOVA SECTOR UI FILE
import {
  Box,
  Button,
  Icon,
  LabeledList,
  NoticeBox,
  Section,
  Stack,
  Table,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

import { useBackend } from '../backend';
import { Window } from '../layouts';

type ShipEntry = {
  id: number;
  name: string;
  tiles: number;
  stored: number;
  status: string;
  retrievable: BooleanLike;
};

type Data = {
  authenticated: BooleanLike;
  operatorName: string | null;
  operatorCkey: string | null;
  registryOnline: BooleanLike;
  statusMessage: string | null;
  zoneLinked: BooleanLike;
  zoneActive: BooleanLike;
  zoneName: string | null;
  zoneWidth: number;
  zoneHeight: number;
  hullName: string | null;
  hullFilable: BooleanLike;
  hullRefusal: string | null;
  surveyReport: string[] | null;
  surveyMatchesHull: BooleanLike;
  ships: ShipEntry[];
};

const LoginView = () => {
  const { act } = useBackend<Data>();

  return (
    <Stack fill vertical>
      <Stack.Item grow />
      <Stack.Item align="center">
        <Icon name="anchor" size={9} color="good" />
      </Stack.Item>
      <Stack.Item align="center">
        <Box color="good" fontSize="18px" bold>
          Nanotrasen Vessel Registry
        </Box>
      </Stack.Item>
      <Stack.Item align="center">
        <Box color="label" italic>
          Long-Term Hull Custody Terminal
        </Box>
      </Stack.Item>
      <Stack.Item align="center">
        <Box color="label" italic>
          Vessels are held against the logged-in operator&apos;s account.
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

const PadPanel = () => {
  const { act, data } = useBackend<Data>();
  const surveyed = !!data.surveyMatchesHull;

  return (
    <Section
      title="Landing Pad"
      buttons={
        <Button icon="rotate" onClick={() => act('refresh')}>
          Refresh
        </Button>
      }
    >
      <LabeledList>
        <LabeledList.Item label="Operator">
          {data.operatorName || 'Unidentified'}
        </LabeledList.Item>
        <LabeledList.Item label="Account">
          {data.operatorCkey || 'unknown'}
        </LabeledList.Item>
        <LabeledList.Item label="Pad">
          {data.zoneActive
            ? `${data.zoneName} (${data.zoneWidth}x${data.zoneHeight})`
            : data.zoneLinked
              ? 'linked, no active zone'
              : 'unlinked'}
        </LabeledList.Item>
        <LabeledList.Item label="On pad">
          {data.hullName || 'nothing'}
        </LabeledList.Item>
      </LabeledList>
      {!!data.hullName && !data.hullFilable && (
        <NoticeBox danger mt={1}>
          Cannot file: {data.hullRefusal}.
        </NoticeBox>
      )}
      <Box mt={1}>
        <Button
          icon="magnifying-glass"
          disabled={!data.hullName}
          onClick={() => act('survey')}
        >
          Survey
        </Button>
        <Button.Confirm
          ml={1}
          icon="box-archive"
          color={surveyed ? 'good' : undefined}
          disabled={!surveyed || !data.hullFilable || !data.registryOnline}
          onClick={() => act('file')}
        >
          File Vessel
        </Button.Confirm>
      </Box>
      {!!data.surveyReport?.length && (
        <Section title="Survey" mt={1}>
          {data.surveyReport.map((line) => (
            <Box key={line} color="label">
              {line}
            </Box>
          ))}
          <Box mt={1} italic color="average">
            Filing keeps the hull and whatever is inside its lockbox. Everything
            else aboard is lost.
          </Box>
        </Section>
      )}
    </Section>
  );
};

const FleetPanel = () => {
  const { act, data } = useBackend<Data>();

  return (
    <Section title="Registered Vessels" fill scrollable>
      {data.ships.length ? (
        <Table>
          <Table.Row header>
            <Table.Cell>Vessel</Table.Cell>
            <Table.Cell collapsing>Tiles</Table.Cell>
            <Table.Cell collapsing>Stored</Table.Cell>
            <Table.Cell collapsing>Status</Table.Cell>
            <Table.Cell collapsing />
          </Table.Row>
          {data.ships.map((ship) => (
            <Table.Row key={ship.id}>
              <Table.Cell>{ship.name}</Table.Cell>
              <Table.Cell collapsing>{ship.tiles}</Table.Cell>
              <Table.Cell collapsing>{ship.stored}</Table.Cell>
              <Table.Cell collapsing color={ship.retrievable ? 'good' : 'label'}>
                {ship.status}
              </Table.Cell>
              <Table.Cell collapsing>
                <Button
                  icon="up-right-from-square"
                  disabled={
                    !ship.retrievable || !data.zoneActive || !!data.hullName
                  }
                  onClick={() => act('retrieve', { id: ship.id })}
                >
                  Retrieve
                </Button>
              </Table.Cell>
            </Table.Row>
          ))}
        </Table>
      ) : (
        <Box color="label" italic>
          No vessels are registered to this account.
        </Box>
      )}
    </Section>
  );
};

const RegistrarView = () => {
  const { act, data } = useBackend<Data>();

  return (
    <Stack fill vertical>
      {!data.registryOnline && (
        <Stack.Item>
          <NoticeBox danger>
            The vessel registry is unreachable. Filing and retrieval are
            unavailable.
          </NoticeBox>
        </Stack.Item>
      )}
      {!!data.statusMessage && (
        <Stack.Item>
          <NoticeBox>{data.statusMessage}</NoticeBox>
        </Stack.Item>
      )}
      <Stack.Item>
        <PadPanel />
      </Stack.Item>
      <Stack.Item grow>
        <FleetPanel />
      </Stack.Item>
      <Stack.Item>
        <Button icon="lock" onClick={() => act('logout')}>
          Log Out
        </Button>
      </Stack.Item>
    </Stack>
  );
};

export const ShipRegistrar = () => {
  const { data } = useBackend<Data>();

  return (
    <Window width={640} height={640}>
      <Window.Content>
        {data.authenticated ? <RegistrarView /> : <LoginView />}
      </Window.Content>
    </Window>
  );
};
