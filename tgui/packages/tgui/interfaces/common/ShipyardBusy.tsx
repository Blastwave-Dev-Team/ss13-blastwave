// THIS IS A NOVA SECTOR UI FILE
import { Box, Dimmer, Icon, Stack } from 'tgui-core/components';

type Props = {
  /** What the counter is in the middle of, or null when it is idle. */
  operation: string | null;
};

/** Covers the whole window while a shipyard counter loads, stores or sells a ship. */
export const ShipyardBusy = (props: Props) => {
  const { operation } = props;
  if (!operation) {
    return null;
  }

  return (
    <Dimmer>
      <Stack vertical align="center" textAlign="center">
        <Stack.Item>
          <Icon name="cog" spin size={4} color="label" />
        </Stack.Item>
        <Stack.Item>
          <Box fontSize="1.4rem" bold>
            {operation}
          </Box>
        </Stack.Item>
        <Stack.Item>
          <Box color="label">Please wait. This console is locked until it finishes.</Box>
        </Stack.Item>
      </Stack>
    </Dimmer>
  );
};
