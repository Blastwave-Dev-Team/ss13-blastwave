// THIS IS A NOVA SECTOR UI FILE
import { useState } from 'react';
import {
  Box,
  Button,
  Icon,
  Input,
  LabeledList,
  NoticeBox,
  Section,
  Stack,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

import { useBackend } from '../backend';
import { Window } from '../layouts';

type CornerEntry = {
  x: number;
  y: number;
  z: number;
  resolved: BooleanLike;
  on_z: BooleanLike;
};

type Data = {
  authenticated: BooleanLike;
  zone_label: string;
  cap: number;
  active: BooleanLike;
  invalid_reason: string | null;
  width: number;
  height: number;
  has_dimensions: BooleanLike;
  oversized: BooleanLike;
  occupied: BooleanLike;
  occupant_name: string | null;
  corners: CornerEntry[];
};

const MAX_CORNERS = 4;

export const OvermapLandingController = () => {
  const { data } = useBackend<Data>();

  return (
    <Window title="Landing Zone Controller" width={420} height={520}>
      <Window.Content>
        {data.authenticated ? <ControllerView /> : <LoginView />}
      </Window.Content>
    </Window>
  );
};

const LoginView = () => {
  const { act } = useBackend<Data>();

  return (
    <Stack fill vertical>
      <Stack.Item grow />
      <Stack.Item align="center">
        <Icon name="satellite-dish" size={9} color="good" />
      </Stack.Item>
      <Stack.Item align="center">
        <Box color="good" fontSize="18px" bold>
          Nanotrasen ApproachNET
        </Box>
      </Stack.Item>
      <Stack.Item align="center">
        <Box color="label" italic>
          Landing Zone Authority Terminal
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

const StatusSection = () => {
  const { data } = useBackend<Data>();
  const { active, invalid_reason, width, height, occupied, occupant_name } =
    data;

  return (
    <Section title="Status">
      {active ? (
        <NoticeBox success>
          Landing zone active &mdash; {width} &times; {height}
        </NoticeBox>
      ) : (
        <NoticeBox danger>Invalid: {invalid_reason || 'no corners'}</NoticeBox>
      )}
      {!!active &&
        (occupied ? (
          <NoticeBox info>Occupied by {occupant_name}</NoticeBox>
        ) : (
          <NoticeBox success>Clear &mdash; ready for landing</NoticeBox>
        ))}
    </Section>
  );
};

const CornerStatus = (props: { corner: CornerEntry }) => {
  const { corner } = props;
  if (!corner.resolved) {
    return (
      <Box as="span" bold color="bad">
        missing
      </Box>
    );
  }
  if (!corner.on_z) {
    return (
      <Box as="span" bold color="average">
        off-Z
      </Box>
    );
  }
  return (
    <Box as="span" bold color="good">
      linked
    </Box>
  );
};

const CornersSection = () => {
  const { act, data } = useBackend<Data>();
  const { corners = [] } = data;
  const emptyCount = Math.max(0, MAX_CORNERS - corners.length);

  return (
    <Section
      title={`Linked Corners (${corners.length}/${MAX_CORNERS})`}
      buttons={
        <>
          <Button icon="rotate" onClick={() => act('validate')}>
            Re-validate
          </Button>
          <Button.Confirm
            icon="xmark"
            color="bad"
            disabled={!corners.length}
            onClick={() => act('clear_corners')}
          >
            Clear all
          </Button.Confirm>
        </>
      }
    >
      <LabeledList>
        {corners.map((corner, index) => (
          <LabeledList.Item key={index} label={`Corner ${index + 1}`}>
            <Box as="span" mr={1}>
              ({corner.x}, {corner.y}, z{corner.z})
            </Box>
            <CornerStatus corner={corner} />
          </LabeledList.Item>
        ))}
        {Array.from({ length: emptyCount }, (_, index) => (
          <LabeledList.Item
            key={`empty-${index}`}
            label={`Corner ${corners.length + index + 1}`}
          >
            <Box as="span" color="label" mr={1}>
              &mdash;
            </Box>
            <Box as="span" bold color="bad">
              unlinked
            </Box>
          </LabeledList.Item>
        ))}
      </LabeledList>
      <Box color="label" italic mt={1}>
        Multitool this console to load it into the buffer, then multitool each
        corner beacon to link it.
      </Box>
    </Section>
  );
};

const ControllerView = () => {
  const { act, data } = useBackend<Data>();
  const { zone_label } = data;
  const [draftName, setDraftName] = useState(zone_label);

  return (
    <Stack fill vertical>
      <Stack.Item>
        <Section title="Zone Designation">
          <Stack fill>
            <Stack.Item grow>
              <Input
                fluid
                value={draftName}
                onChange={(value) => setDraftName(value)}
                onEnter={(value) => act('set_name', { name: value })}
              />
            </Stack.Item>
            <Stack.Item>
              <Button
                icon="check"
                onClick={() => act('set_name', { name: draftName })}
              >
                Rename
              </Button>
            </Stack.Item>
          </Stack>
        </Section>
      </Stack.Item>
      <Stack.Item>
        <StatusSection />
      </Stack.Item>
      <Stack.Item grow>
        <CornersSection />
      </Stack.Item>
      <Stack.Item>
        <NoticeBox info align="right">
          Secure your workspace.
          <Button
            ml={2}
            icon="lock"
            color="good"
            onClick={() => act('logout')}
          >
            Log Out
          </Button>
        </NoticeBox>
      </Stack.Item>
    </Stack>
  );
};
