// THIS IS A NOVA SECTOR UI FILE
import { useState } from 'react';
import { Box, Button, Input, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

import { useBackend } from '../backend';
import { Window } from '../layouts';

type DistressBeaconData = {
  transmitting: BooleanLike;
  shuttle_status: string | null;
  shuttle_called: BooleanLike;
  security_level: number;
  can_call: BooleanLike;
};

export const DistressBeacon = () => {
  const { act, data } = useBackend<DistressBeaconData>();
  const {
    transmitting,
    shuttle_status,
    shuttle_called,
    security_level,
    can_call,
  } = data;
  const [reason, setReason] = useState('');

  return (
    <Window width={380} height={220} title="Distress Beacon">
      <Window.Content>
        <Stack fill vertical>
          <Stack.Item>
            <Section title="Emergency Evacuation">
              {shuttle_called ? (
                <Box color="good">
                  Evacuation shuttle has been called.
                  {shuttle_status && <Box mt={1}>Status: {shuttle_status}</Box>}
                </Box>
              ) : transmitting ? (
                <Box color="average">Distress signal transmitting...</Box>
              ) : security_level <= 0 ? (
                <Box color="bad">
                  Cannot call evacuation at current security level.
                </Box>
              ) : (
                <Stack vertical>
                  <Stack.Item>
                    <Input
                      fluid
                      placeholder="Reason for evacuation (min 10 characters)"
                      value={reason}
                      onChange={(value) => setReason(value)}
                    />
                  </Stack.Item>
                  <Stack.Item>
                    <Button
                      fluid
                      icon="exclamation-triangle"
                      color="bad"
                      disabled={!can_call || reason.length < 10}
                      onClick={() => act('call_evac', { reason })}
                    >
                      Call Emergency Shuttle
                    </Button>
                  </Stack.Item>
                </Stack>
              )}
            </Section>
          </Stack.Item>
        </Stack>
      </Window.Content>
    </Window>
  );
};
