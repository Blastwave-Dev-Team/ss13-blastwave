// THIS IS A NOVA SECTOR UI FILE
import { type CSSProperties, type ReactNode, useState } from 'react';
import {
  Box,
  Button,
  Collapsible,
  Icon,
  LabeledList,
  NoticeBox,
  Section,
  Stack,
  Table,
  Tabs,
  Tooltip,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { classes } from 'tgui-core/react';

import { useBackend } from '../backend';
import { Window } from '../layouts';
import { ShipyardBusy } from './common/ShipyardBusy';
import { ShipyardPin } from './common/ShipyardPin';

type ShipStatus = 'FILED' | 'CHECKED_OUT' | 'LOST';

type Ownership = 'PERSONAL' | 'DEPARTMENT' | 'STATION';

type RefusalCode =
  | 'living_mob'
  | 'outside_zone'
  | 'not_idle'
  | 'mid_build'
  | 'station_hull'
  | 'department_hull'
  | 'other_owner'
  | 'unfilable';

type TileFate = 'kept' | 'lockbox' | 'lost' | 'unrouted';

type GrantKind = 'DONATOR' | 'EVENT' | 'ADMIN';

type Silhouette = { width: number; height: number; cells: BooleanLike[] };

type ShipEntry = {
  id: number;
  name: string;
  revision: number;
  tiles: number;
  lockboxCount: number;
  salvageEstimate: number;
  status: ShipStatus;
  insured: BooleanLike;
  retrievedThisRound: BooleanLike;
  revertedFromLoss: BooleanLike;
  quote: { insured: number; uninsured: number };
  silhouette: Silhouette | null;
  scrapValue: number;
  blueprintPrinted: BooleanLike;
  blueprintFee: number;
  grant: string | null;
};

type LockboxLine = {
  name: string;
  count: number;
  appraisal: number;
  floored: BooleanLike;
};

type FootprintTile = { fate: TileFate; objects: string[] } | null;

type Survey = {
  tiles: number;
  kept: string[];
  lost: string[];
  unrouted: string[];
  lostDecals: number;
  lockbox: LockboxLine[];
  footprint: { width: number; height: number; tiles: FootprintTile[] };
  quote: {
    base: number;
    tileFee: number;
    lockboxFee: number;
    storage: number;
    insuranceRefund: number;
    net: number;
  };
};

type Occupant = {
  name: string;
  ownership: Ownership;
  ownedByOperator: BooleanLike;
  registryId: number | null;
  rebuilt: BooleanLike;
};

type Zone = {
  linked: BooleanLike;
  name: string | null;
  width: number;
  height: number;
  occupant: Occupant | null;
};

type Refusal = { code: RefusalCode; text: string; blocksSurvey: BooleanLike };

type StatusMessage = { kind: 'good' | 'bad'; text: string };

type SlotGrant = { kind: GrantKind; source: string; count: number };

type Slots = {
  base: number;
  grants: SlotGrant[];
  total: number;
  used: number;
  elsewhere: number;
};

type Data = {
  authenticated: BooleanLike;
  operatorName: string | null;
  characterName: string | null;
  ledgerBalance: number | null;
  registryOnline: BooleanLike;
  ledgerOnline: BooleanLike;
  zone: Zone;
  refusal: Refusal | null;
  survey: Survey | null;
  ships: ShipEntry[];
  slots: Slots;
  statusMessage: StatusMessage | null;
  busy: string | null;
};

type RegistrarTab = 'PAD' | 'GARAGE';

/** A retrieval picked in the garage, waiting for coverage on the pad tab. */
type Staged = { id: number; insured: boolean | null };

const credits = (amount: number) =>
  `${Math.round(amount).toLocaleString('en-US')} cr`;

const plural = (count: number, word: string) =>
  `${count} ${word}${count === 1 ? '' : 's'}`;

const coverageRule = (ship: ShipEntry, insured: boolean) =>
  insured
    ? `If the hull is lost, the garage keeps revision ${ship.revision}. Filing it again refunds the fee against storage.`
    : 'If the hull is lost, or not filed before the shift ends, the ship is gone for good.';

const LoginView = () => {
  const { act, data } = useBackend<Data>();

  return (
    <Stack fill vertical>
      <Stack.Item grow />
      <Stack.Item align="center">
        <Icon name="anchor" size={9} color="good" />
      </Stack.Item>
      <Stack.Item align="center">
        <Box color="good" fontSize="18px" bold mt={2}>
          Nanotrasen Vessel Registry
        </Box>
      </Stack.Item>
      <Stack.Item align="center">
        <Box color="label" italic>
          Swipe an ID to file ships and open your garage.
        </Box>
      </Stack.Item>
      {!data.registryOnline && (
        <Stack.Item align="center">
          <NoticeBox danger mt={1}>
            Hangar registry offline. Filing and retrieval are unavailable.
          </NoticeBox>
        </Stack.Item>
      )}
      <Stack.Item align="center">
        <Button icon="sign-in-alt" mt={1} onClick={() => act('login')}>
          Log in
        </Button>
      </Stack.Item>
      <Stack.Item grow />
    </Stack>
  );
};

const StatusNotice = (props: { message: StatusMessage }) => {
  const { message } = props;
  switch (message.kind) {
    case 'good':
      return (
        <NoticeBox success mt={1}>
          {message.text}
        </NoticeBox>
      );
    case 'bad':
      return (
        <NoticeBox danger mt={1}>
          {message.text}
        </NoticeBox>
      );
    default: {
      const unhandled: never = message.kind;
      throw new Error(`unhandled status kind ${unhandled}`);
    }
  }
};

const HeaderView = () => {
  const { act, data } = useBackend<Data>();

  return (
    <Section>
      <Stack align="center">
        <Stack.Item>
          <Icon name="id-card" color="good" size={1.5} />
        </Stack.Item>
        <Stack.Item grow>
          <Box bold>{data.characterName || 'Unknown'}</Box>
          <Box color="label" fontSize="0.9em">
            {data.operatorName || 'Unidentified'}
          </Box>
        </Stack.Item>
        <Stack.Item>
          {data.ledgerOnline && data.ledgerBalance !== null ? (
            <Box bold>{credits(data.ledgerBalance)}</Box>
          ) : (
            <Box color="average">
              <Icon name="exclamation-triangle" /> Ledger offline
            </Box>
          )}
        </Stack.Item>
        <Stack.Item>
          <Button
            icon="rotate"
            tooltip="Refresh"
            onClick={() => act('refresh')}
          />
        </Stack.Item>
        <Stack.Item>
          <Button icon="sign-out-alt" onClick={() => act('logout')}>
            Log out
          </Button>
        </Stack.Item>
      </Stack>
      {!data.registryOnline && (
        <NoticeBox danger mt={1}>
          Hangar registry offline. Surveys still work, but nothing can be filed
          or retrieved.
        </NoticeBox>
      )}
      {!!data.statusMessage && <StatusNotice message={data.statusMessage} />}
    </Section>
  );
};

const OwnershipLabel = (props: { occupant: Occupant }) => {
  const { occupant } = props;
  switch (occupant.ownership) {
    case 'PERSONAL':
      return occupant.ownedByOperator ? (
        <Box inline color="good">
          <Icon name="user" /> Personal, yours
        </Box>
      ) : (
        <Box inline color="bad">
          <Icon name="user-lock" /> Personal, another captain
        </Box>
      );
    case 'DEPARTMENT':
      return (
        <Box inline color="average">
          <Icon name="users" /> Department, station property
        </Box>
      );
    case 'STATION':
      return (
        <Box inline color="average">
          <Icon name="building" /> Station property
        </Box>
      );
    default: {
      const unhandled: never = occupant.ownership;
      throw new Error(`unhandled ownership ${unhandled}`);
    }
  }
};

const surveyDisabledReason = (data: Data) => {
  if (!data.zone.linked) {
    return 'No landing pad linked. Use a multitool on a landing controller.';
  }
  if (!data.zone.occupant) {
    return 'The pad is empty.';
  }
  if (data.refusal?.blocksSurvey) {
    return data.refusal.text;
  }
  return null;
};

const occupantRecord = (data: Data) => {
  const registryId = data.zone.occupant?.registryId;
  return registryId
    ? data.ships.find((ship) => ship.id === registryId) || null
    : null;
};

const fileDisabledReason = (data: Data) => {
  if (!data.registryOnline) {
    return 'Hangar registry offline.';
  }
  if (!data.ledgerOnline) {
    return 'Ledger offline. Fees cannot be charged.';
  }
  if (!data.zone.occupant) {
    return 'The pad is empty.';
  }
  if (data.refusal) {
    return data.refusal.text;
  }
  const { used, total } = data.slots;
  const own = occupantRecord(data);
  if (!own && used >= total) {
    return `Garage full (${used} / ${total} slots). Decommission a stored ship or clear a lost one to free a slot.`;
  }
  if (own && own.status !== 'FILED' && used > total) {
    return `Garage over its slot limit (${used} / ${total}). Clear or decommission another ship before filing this one back in.`;
  }
  if (!data.survey) {
    return 'Run a survey first so you can see what will be kept and what will be lost.';
  }
  if ((data.ledgerBalance ?? 0) < data.survey.quote.net) {
    return `Not enough credits. Filing costs ${credits(data.survey.quote.net)}.`;
  }
  return null;
};

const retrieveDisabledReason = (data: Data, ship: ShipEntry) => {
  switch (ship.status) {
    case 'CHECKED_OUT':
      return 'Already deployed this shift.';
    case 'LOST':
      return 'This hull was lost.';
    case 'FILED':
      break;
    default: {
      const unhandled: never = ship.status;
      throw new Error(`unhandled ship status ${unhandled}`);
    }
  }
  if (!data.ledgerOnline) {
    return 'Ledger offline. Fees cannot be charged.';
  }
  if (!data.zone.linked) {
    return 'No landing pad linked.';
  }
  if (data.zone.occupant) {
    return `${data.zone.name} is occupied. Clear the pad first.`;
  }
  return null;
};

const PadTab = (props: {
  staged: Staged | null;
  setStaged: (staged: Staged | null) => void;
  openGarage: () => void;
}) => {
  const { act, data } = useBackend<Data>();
  const { zone, survey, refusal } = data;
  const occupant = zone.occupant;
  const surveyBlock = surveyDisabledReason(data);
  const stagedShip = props.staged
    ? data.ships.find((ship) => ship.id === props.staged?.id)
    : null;

  if (!zone.linked) {
    return (
      <Section title="Landing Pad" fill>
        <NoticeBox info>
          No landing pad linked. Use a multitool on a landing controller, then
          on this console.
        </NoticeBox>
      </Section>
    );
  }

  let side: ReactNode;
  if (!occupant) {
    side = (
      <RetrievalPanel
        staged={props.staged}
        setStaged={props.setStaged}
        openGarage={props.openGarage}
      />
    );
  } else if (survey) {
    side = (
      <Section title="Survey details" fill scrollable>
        <SurveyDetails survey={survey} />
      </Section>
    );
  } else {
    side = (
      <Section title="Survey details" fill>
        <Box color="label" italic>
          Run a survey to see what is kept, what is destroyed, and the lockbox
          appraisal.
        </Box>
      </Section>
    );
  }

  return (
    <Stack fill>
      <Stack.Item basis="50%">
        <Section
          title="Landing Pad"
          fill
          scrollable
          buttons={
            !!occupant && (
              <Button
                icon="search"
                disabled={!!surveyBlock}
                tooltip={surveyBlock}
                onClick={() => act('survey')}
              >
                {survey ? 'Re-survey' : 'Survey'}
              </Button>
            )
          }
        >
          <LabeledList>
            <LabeledList.Item label="Pad">
              {zone.name}{' '}
              <Box inline color="label">
                {zone.width} x {zone.height}
              </Box>
            </LabeledList.Item>
            <LabeledList.Item label="Occupant">
              {occupant ? (
                <Box inline bold>
                  {occupant.name}
                </Box>
              ) : (
                <Box inline color="label" italic>
                  Empty
                </Box>
              )}
            </LabeledList.Item>
            {!!occupant && (
              <LabeledList.Item label="Ownership">
                <OwnershipLabel occupant={occupant} />
              </LabeledList.Item>
            )}
            {!!occupant && (
              <LabeledList.Item label="Registry">
                {occupant.registryId ? (
                  <>
                    Registry #{occupant.registryId}
                    {!!occupant.rebuilt && (
                      <Box inline color="label" ml={1}>
                        rebuilt from blueprint
                      </Box>
                    )}
                  </>
                ) : (
                  <Box inline color="label" italic>
                    Not registered yet, first filing
                  </Box>
                )}
              </LabeledList.Item>
            )}
          </LabeledList>
          {!!refusal && (
            <NoticeBox danger mt={1}>
              <Icon name="ban" /> {refusal.text}
            </NoticeBox>
          )}
          {!!occupant && !!stagedShip && (
            <NoticeBox color="average" mt={1}>
              <Icon name="hourglass-half" /> {stagedShip.name} is waiting to be
              retrieved. File or launch {occupant.name} to clear the pad first.{' '}
              <Button compact onClick={() => props.setStaged(null)}>
                Cancel
              </Button>
            </NoticeBox>
          )}
          {!!survey && <SurveySummary survey={survey} />}
          {!!occupant && <FileControls />}
        </Section>
      </Stack.Item>
      <Stack.Item grow>{side}</Stack.Item>
    </Stack>
  );
};

const SurveySummary = (props: { survey: Survey }) => {
  const { survey } = props;
  const lockboxItems = survey.lockbox.reduce(
    (sum, line) => sum + line.count,
    0,
  );

  return (
    <Section title="Survey" mt={1}>
      <LabeledList>
        <LabeledList.Item label="Tiles">{survey.tiles}</LabeledList.Item>
        <LabeledList.Item label="Kept" color="good">
          {plural(survey.kept.length, 'group')}
        </LabeledList.Item>
        <LabeledList.Item
          label="Destroyed"
          color={survey.lost.length ? 'average' : undefined}
        >
          {plural(survey.lost.length, 'object')}
        </LabeledList.Item>
        <LabeledList.Item
          label="No route"
          color={survey.unrouted.length ? 'bad' : undefined}
        >
          {plural(survey.unrouted.length, 'object')}
        </LabeledList.Item>
        <LabeledList.Item
          label="Lost decals"
          color={survey.lostDecals ? 'average' : undefined}
        >
          {survey.lostDecals}
        </LabeledList.Item>
        <LabeledList.Item label="Lockbox" color="good">
          {plural(lockboxItems, 'item')} kept
        </LabeledList.Item>
      </LabeledList>
    </Section>
  );
};

const NameList = (props: { items: string[]; color: string }) => (
  <>
    {props.items.map((item) => (
      <Box key={item} color={props.color}>
        <Icon name="angle-right" /> {item}
      </Box>
    ))}
  </>
);

const SurveyDetails = (props: { survey: Survey }) => {
  const { survey } = props;

  return (
    <>
      <Collapsible title={`Kept (${survey.kept.length})`}>
        <NameList items={survey.kept} color="good" />
      </Collapsible>
      {!!survey.lost.length && (
        <Collapsible title={`Destroyed on filing (${survey.lost.length})`}>
          <NameList items={survey.lost} color="average" />
        </Collapsible>
      )}
      {!!survey.unrouted.length && (
        <Collapsible
          title={`No construction route (${survey.unrouted.length})`}
        >
          <NameList items={survey.unrouted} color="bad" />
        </Collapsible>
      )}
      <Collapsible title="Lockbox appraisal">
        {survey.lockbox.length ? (
          <Table>
            {survey.lockbox.map((line) => (
              <Table.Row key={line.name}>
                <Table.Cell>
                  {line.name}
                  {line.count > 1 && (
                    <Box inline color="label" ml={1}>
                      x{line.count}
                    </Box>
                  )}
                </Table.Cell>
                <Table.Cell collapsing textAlign="right">
                  {line.floored ? (
                    <Tooltip content="No export value. Charged at the flat per-item floor.">
                      <Box inline color="average">
                        {credits(line.appraisal)}
                      </Box>
                    </Tooltip>
                  ) : (
                    credits(line.appraisal)
                  )}
                </Table.Cell>
              </Table.Row>
            ))}
          </Table>
        ) : (
          <Box color="label" italic>
            The lockbox is empty.
          </Box>
        )}
      </Collapsible>
      <Collapsible title="Footprint">
        <Footprint footprint={survey.footprint} />
      </Collapsible>
    </>
  );
};

const FATE_LABELS: Record<TileFate, string> = {
  kept: 'Kept',
  lockbox: 'Lockbox',
  lost: 'Detail lost',
  unrouted: 'No route',
};

const Footprint = (props: { footprint: Survey['footprint'] }) => {
  const { width, height, tiles } = props.footprint;

  return (
    <>
      <div className="ShipRegistrar__footprint">
        <div
          className="ShipRegistrar__footprint-grid"
          style={{ '--w': width, '--h': height } as CSSProperties}
        >
          {tiles.map((tile, index) => {
            const x = (index % width) + 1;
            const y = Math.floor(index / width) + 1;
            return tile ? (
              <div
                key={index}
                className={`ShipRegistrar__tile ShipRegistrar__tile--${tile.fate}`}
                title={[`Tile ${x}, ${y}`, ...tile.objects].join('\n')}
              />
            ) : (
              <div key={index} />
            );
          })}
        </div>
      </div>
      <Box textAlign="center">
        {(Object.keys(FATE_LABELS) as TileFate[]).map((fate) => (
          <Box key={fate} inline mr={1} color="label">
            <span
              className={`ShipRegistrar__tile--${fate} ShipRegistrar__swatch`}
            />
            {FATE_LABELS[fate]}
          </Box>
        ))}
      </Box>
    </>
  );
};

const SlotLine = () => {
  const { data } = useBackend<Data>();
  const { used, total } = data.slots;
  const own = occupantRecord(data);

  if (!own) {
    return used >= total ? (
      <LabeledList.Item label="Garage slot" color="bad">
        Garage full, {used} / {total}
      </LabeledList.Item>
    ) : (
      <LabeledList.Item label="Garage slot">
        Takes 1 of {total - used} free ({used} / {total} used)
      </LabeledList.Item>
    );
  }
  if (own.status !== 'FILED' && used > total) {
    return (
      <LabeledList.Item label="Garage slot" color="bad">
        Over the limit, {used} / {total}. Cannot be filed back in.
      </LabeledList.Item>
    );
  }
  if (own.status === 'LOST') {
    return (
      <LabeledList.Item label="Garage slot" color="good">
        Restores its lost slot
      </LabeledList.Item>
    );
  }
  return (
    <LabeledList.Item label="Garage slot">
      Refiles into its own slot ({used} / {total} used)
    </LabeledList.Item>
  );
};

const FileControls = () => {
  const { act, data } = useBackend<Data>();
  const [pin, setPin] = useState('');
  const reason = fileDisabledReason(data);
  const quote = data.survey?.quote;
  const balance = data.ledgerBalance ?? 0;
  const pinBlock = pin.length < 1 ? 'Enter your ledger PIN to file.' : null;

  return (
    <Section title="File to garage" mt={1}>
      <LabeledList>
        <SlotLine />
        {!!quote && (
          <>
            <LabeledList.Item label="Storage fee">
              {credits(quote.storage)}{' '}
              <Box inline color="label">
                ({quote.base.toLocaleString('en-US')} base +{' '}
                {quote.tileFee.toLocaleString('en-US')} hull +{' '}
                {quote.lockboxFee.toLocaleString('en-US')} lockbox)
              </Box>
            </LabeledList.Item>
            {quote.insuranceRefund > 0 && (
              <LabeledList.Item label="Insurance refund">
                <Tooltip content="Refunded insurance only offsets this storage fee. Any remainder is not returned.">
                  <Box inline color="good">
                    {credits(quote.insuranceRefund)}, applied up to the storage
                    fee
                  </Box>
                </Tooltip>
              </LabeledList.Item>
            )}
            <LabeledList.Item label="Net charge">
              <Box inline bold>
                {credits(quote.net)}
              </Box>
            </LabeledList.Item>
            {!!data.ledgerOnline && (
              <LabeledList.Item
                label="Balance after"
                color={balance < quote.net ? 'bad' : undefined}
              >
                {credits(balance - quote.net)}
              </LabeledList.Item>
            )}
          </>
        )}
        <ShipyardPin value={pin} onChange={setPin} />
      </LabeledList>
      <Box color="label" italic mt={1} mb={1}>
        Filing removes the hull from the pad. Anything not kept is destroyed.
      </Box>
      <Button.Confirm
        fluid
        icon="archive"
        color="good"
        textAlign="center"
        disabled={!!reason || !!pinBlock}
        tooltip={reason || pinBlock}
        onClick={() => act('file', { pin })}
      >
        File ship
      </Button.Confirm>
    </Section>
  );
};

const RetrievalPanel = (props: {
  staged: Staged | null;
  setStaged: (staged: Staged | null) => void;
  openGarage: () => void;
}) => {
  const { act, data } = useBackend<Data>();
  const [pin, setPin] = useState('');
  const { staged, setStaged } = props;
  const ship = staged
    ? data.ships.find((entry) => entry.id === staged.id)
    : null;

  if (!staged || !ship) {
    return (
      <Section title="Retrieve" fill>
        <NoticeBox info>
          The pad is clear. Pick a ship in the Garage and choose Retrieve to
          pad.
        </NoticeBox>
        <Button icon="warehouse" onClick={props.openGarage}>
          Open garage
        </Button>
      </Section>
    );
  }
  const balance = data.ledgerBalance ?? 0;
  const pick = staged.insured;
  const fee =
    pick === null ? null : pick ? ship.quote.insured : ship.quote.uninsured;
  const reason =
    retrieveDisabledReason(data, ship) ||
    (pick === null ? 'Choose coverage first.' : null) ||
    (pin.length < 1 ? 'Enter your ledger PIN to retrieve.' : null);

  const option = (insured: boolean) => {
    const optionFee = insured ? ship.quote.insured : ship.quote.uninsured;
    const short = balance < optionFee;
    return (
      <Button
        fluid
        mb={0.5}
        icon={insured ? 'shield-alt' : 'exclamation-triangle'}
        selected={pick === insured}
        disabled={short}
        tooltip={
          short
            ? `Not enough credits. You need ${credits(optionFee)}.`
            : coverageRule(ship, insured)
        }
        onClick={() => setStaged({ id: ship.id, insured })}
      >
        {insured ? 'Insured' : 'Uninsured'}
        <Box inline bold ml={0.5}>
          {credits(optionFee)}
        </Box>
      </Button>
    );
  };

  return (
    <Section
      title={`Retrieve ${ship.name}`}
      fill
      scrollable
      buttons={
        <Button icon="times" onClick={() => setStaged(null)}>
          Cancel
        </Button>
      }
    >
      <LabeledList>
        <LabeledList.Item label="Destination">
          {data.zone.name}{' '}
          <Box inline color="label">
            {data.zone.width} x {data.zone.height}
          </Box>
        </LabeledList.Item>
        <LabeledList.Item label="Revision">
          {ship.revision}, {ship.tiles} tiles,{' '}
          {plural(ship.lockboxCount, 'lockbox item')}
        </LabeledList.Item>
        <LabeledList.Item label="Salvage estimate">
          {credits(ship.salvageEstimate)}
        </LabeledList.Item>
        <LabeledList.Item label="Ledger balance">
          {credits(balance)}
        </LabeledList.Item>
        {fee !== null && (
          <LabeledList.Item label="Balance after">
            {credits(balance - fee)}
          </LabeledList.Item>
        )}
      </LabeledList>
      <Box bold mt={1} mb={0.5}>
        Coverage
      </Box>
      {option(true)}
      {option(false)}
      {pick !== null && (
        <Box color="label" mb={1}>
          {coverageRule(ship, pick)}
        </Box>
      )}
      {pick === false && (
        <NoticeBox color="average" mb={1}>
          If {ship.name} is not filed before the shift ends, it is marked lost.
          It keeps its slot until you clear it or rebuild it from a blueprint.
        </NoticeBox>
      )}
      <LabeledList>
        <ShipyardPin value={pin} onChange={setPin} />
      </LabeledList>
      <Button
        fluid
        textAlign="center"
        icon="plane-arrival"
        color="good"
        disabled={!!reason}
        tooltip={reason}
        onClick={() => {
          act('retrieve', { id: ship.id, insured: pick ? 1 : 0, pin });
          setStaged(null);
        }}
      >
        {fee === null ? 'Retrieve' : `Retrieve for ${credits(fee)}`}
      </Button>
    </Section>
  );
};

const StatusLine = (props: {
  icon: string;
  text: string;
  color: string;
  detail?: string | null;
}) => (
  <>
    <Box color={props.color} nowrap>
      <Icon name={props.icon} /> {props.text}
    </Box>
    {!!props.detail && (
      <Box color="label" fontSize="0.9em">
        {props.detail}
      </Box>
    )}
  </>
);

const StatusCell = (props: { ship: ShipEntry }) => {
  const { ship } = props;
  switch (ship.status) {
    case 'FILED':
      return (
        <StatusLine
          icon="warehouse"
          text="In storage"
          color="good"
          detail={
            ship.revertedFromLoss
              ? 'Reverted to last filing after an insured loss'
              : null
          }
        />
      );
    case 'CHECKED_OUT':
      return ship.insured ? (
        <StatusLine
          icon="shield-alt"
          text="Deployed, insured"
          color="good"
          detail={`A loss restores revision ${ship.revision}`}
        />
      ) : (
        <StatusLine
          icon="exclamation-triangle"
          text="Deployed, uninsured"
          color="average"
          detail="File before the shift ends or it is lost"
        />
      );
    case 'LOST':
      return (
        <StatusLine
          icon="skull"
          text="Lost"
          color="bad"
          detail={
            ship.blueprintPrinted
              ? 'Blueprint printed. Rebuild it and file it here to restore this slot.'
              : 'Deployed uninsured and never filed. The slot stays taken until you clear it.'
          }
        />
      );
    default: {
      const unhandled: never = ship.status;
      throw new Error(`unhandled ship status ${unhandled}`);
    }
  }
};

const SlotBadge = (props: { ship: ShipEntry }) => {
  const { ship } = props;
  switch (ship.status) {
    case 'FILED':
      return ship.revertedFromLoss ? (
        <Icon name="history" color="blue" />
      ) : (
        <Icon name="warehouse" color="good" />
      );
    case 'CHECKED_OUT':
      return ship.insured ? (
        <Icon name="shield-alt" color="good" />
      ) : (
        <Icon name="exclamation-triangle" color="average" />
      );
    case 'LOST':
      return <Icon name="skull" color="bad" />;
    default: {
      const unhandled: never = ship.status;
      throw new Error(`unhandled ship status ${unhandled}`);
    }
  }
};

const slotTooltip = (ship: ShipEntry) => {
  const head = `${ship.name}, rev ${ship.revision}`;
  switch (ship.status) {
    case 'FILED':
      return `${head}\nIn storage${ship.revertedFromLoss ? ', reverted after an insured loss' : ''}`;
    case 'CHECKED_OUT':
      return `${head}\nDeployed, ${ship.insured ? 'insured' : 'uninsured'}`;
    case 'LOST':
      return `${head}\nLost, still holding its slot`;
    default: {
      const unhandled: never = ship.status;
      throw new Error(`unhandled ship status ${unhandled}`);
    }
  }
};

const GrantIcon = (props: { kind: GrantKind }) => {
  switch (props.kind) {
    case 'DONATOR':
      return <Icon name="star" color="yellow" />;
    case 'EVENT':
      return <Icon name="gift" color="purple" />;
    case 'ADMIN':
      return <Icon name="user-shield" color="blue" />;
    default: {
      const unhandled: never = props.kind;
      throw new Error(`unhandled grant kind ${unhandled}`);
    }
  }
};

/** The hull's footprint, or a stand-in when its map could not be read. */
const ShipIcon = (props: { ship: ShipEntry }) => {
  const { silhouette } = props.ship;
  if (!silhouette) {
    return <Icon name="rocket" size={2} color="label" />;
  }
  return (
    <div
      className="ShipRegistrar__silhouette"
      style={
        { '--w': silhouette.width, '--h': silhouette.height } as CSSProperties
      }
    >
      {silhouette.cells.map((on, index) => (
        <div key={index} className={on ? 'on' : undefined} />
      ))}
    </div>
  );
};

const SlotMeter = (props: { used: number; total: number }) => {
  const { used, total } = props;
  return (
    <span className="ShipRegistrar__meter">
      {Array.from({ length: Math.max(used, total) }, (_, index) => (
        <span
          key={index}
          className={index >= total ? 'over' : index < used ? 'on' : undefined}
        />
      ))}
    </span>
  );
};

const SlotGrid = (props: {
  selectedId: number | null;
  onSelect: (id: number) => void;
}) => {
  const { data } = useBackend<Data>();
  const { used, total, elsewhere } = data.slots;
  // Only this character's ships are listed; the rest of the ckey's pool shows
  // as occupied slots with no detail.
  const cellCount = Math.max(total, used);
  const cells: ReactNode[] = [];
  for (let index = 0; index < cellCount; index++) {
    const ship = data.ships[index];
    const over = index >= total;
    if (ship) {
      const deployed = ship.status === 'CHECKED_OUT';
      const lost = ship.status === 'LOST';
      const tooltip = [
        slotTooltip(ship),
        ship.grant && `Awarded: ${ship.grant}`,
        over && 'Garage over its limit',
      ]
        .filter(Boolean)
        .join('\n');
      cells.push(
        <Tooltip key={`ship-${ship.id}`} content={tooltip}>
          <div
            className={classes([
              'ShipRegistrar__slot',
              ship.id === props.selectedId && 'ShipRegistrar__slot--selected',
              deployed && 'ShipRegistrar__slot--deployed',
              lost && 'ShipRegistrar__slot--lost',
              over && 'ShipRegistrar__slot--over',
            ])}
            onClick={() => props.onSelect(ship.id)}
          >
            {!!ship.grant && (
              <div className="ShipRegistrar__slot-grant">
                <Icon name="gift" color="purple" />
              </div>
            )}
            <div className="ShipRegistrar__slot-badge">
              <SlotBadge ship={ship} />
            </div>
            <div className="ShipRegistrar__slot-icon">
              <ShipIcon ship={ship} />
            </div>
            <div className="ShipRegistrar__slot-label">
              <b>{ship.name}</b>
            </div>
            <Box color="label" fontSize="0.85em">
              rev {ship.revision}
            </Box>
          </div>
        </Tooltip>,
      );
      continue;
    }
    if (index < data.ships.length + elsewhere) {
      cells.push(
        <div
          key={`elsewhere-${index}`}
          className={classes([
            'ShipRegistrar__slot',
            'ShipRegistrar__slot--empty',
            over && 'ShipRegistrar__slot--over',
          ])}
        >
          <Icon name="user" size={1.5} color="label" />
          <div className="ShipRegistrar__slot-label">Another character</div>
        </div>,
      );
      continue;
    }
    cells.push(
      <div
        key={`empty-${index}`}
        className="ShipRegistrar__slot ShipRegistrar__slot--empty"
      >
        <Box opacity={0.5}>
          <Icon name="plus" size={1.5} color="label" />
        </Box>
        <div className="ShipRegistrar__slot-label">Empty slot</div>
      </div>,
    );
  }

  return (
    <Section
      title={
        <>
          Garage{' '}
          <Box inline color={used > total ? 'bad' : 'label'}>
            {used} / {total} slots
          </Box>
          <SlotMeter used={used} total={total} />
        </>
      }
      fill
      scrollable
    >
      {!data.ships.length && (
        <NoticeBox info mb={1}>
          Your garage is empty. Print or buy a hull, land it on the pad, and
          file it from the Landing Pad tab.
        </NoticeBox>
      )}
      <div className="ShipRegistrar__slots">{cells}</div>
      <Box color="label" mt={1}>
        {data.slots.base} base
        {data.slots.grants.map((grant, index) => (
          <span key={index}>
            {' · '}
            <GrantIcon kind={grant.kind} /> {grant.count} {grant.source}
          </span>
        ))}
      </Box>
      {used > total && (
        <NoticeBox color="average" mt={1}>
          Over the slot limit by {used - total}. Ships can still leave the
          garage, but ones that leave cannot be filed back in until you are
          under the limit.
        </NoticeBox>
      )}
    </Section>
  );
};

const ShipDetail = (props: {
  ship: ShipEntry | null;
  staged: Staged | null;
  onStage: (id: number) => void;
  openPad: () => void;
}) => {
  const { act, data } = useBackend<Data>();
  const [pin, setPin] = useState('');
  const { ship } = props;

  if (!ship) {
    return (
      <Section title="Details" fill>
        <Box color="label" italic>
          Select a ship to see its record.
        </Box>
      </Section>
    );
  }
  const balance = data.ledgerBalance ?? 0;
  const reason = retrieveDisabledReason(data, ship);
  const isStaged = props.staged?.id === ship.id;
  const scrapBlock = !data.ledgerOnline
    ? 'Ledger offline. The payout cannot be credited.'
    : null;
  let printBlock: string | null = null;
  if (ship.blueprintPrinted) {
    printBlock = 'A disk was already dispensed this shift.';
  } else if (!data.ledgerOnline) {
    printBlock = 'Ledger offline. The fee cannot be charged.';
  } else if (balance < ship.blueprintFee) {
    printBlock = `Not enough credits. The blueprint costs ${credits(ship.blueprintFee)}.`;
  } else if (pin.length < 1) {
    printBlock = 'Enter your ledger PIN to print.';
  }
  const cannotReturn =
    ship.status !== 'FILED' && data.slots.used > data.slots.total;

  return (
    <Section
      title={
        <>
          {ship.name}{' '}
          <Box inline color="label">
            #{ship.id}
          </Box>
        </>
      }
      fill
      scrollable
    >
      <div className="ShipRegistrar__detail-icon">
        <div className="ShipRegistrar__slot-icon ShipRegistrar__slot-icon--large">
          <ShipIcon ship={ship} />
        </div>
      </div>
      <LabeledList>
        <LabeledList.Item label="Revision">{ship.revision}</LabeledList.Item>
        <LabeledList.Item label="Tiles">{ship.tiles}</LabeledList.Item>
        <LabeledList.Item label="Lockbox">
          {plural(ship.lockboxCount, 'item')}
        </LabeledList.Item>
        <LabeledList.Item label="Salvage">
          {credits(ship.salvageEstimate)}
        </LabeledList.Item>
      </LabeledList>
      {!!ship.grant && (
        <Box mt={1}>
          <Icon name="gift" color="purple" /> Awarded: {ship.grant}
        </Box>
      )}
      <Box mt={1} mb={1}>
        <StatusCell ship={ship} />
      </Box>
      {cannotReturn && (
        <NoticeBox color="average" mb={1}>
          The garage is over its limit, so {ship.name} cannot be filed back in
          yet.
        </NoticeBox>
      )}
      {ship.status === 'LOST' && (
        <LabeledList>
          <ShipyardPin value={pin} onChange={setPin} />
        </LabeledList>
      )}
      {ship.status === 'LOST' ? (
        <>
          <Button
            fluid
            textAlign="center"
            icon="compact-disc"
            color="good"
            mb={0.5}
            disabled={!!printBlock}
            tooltip={
              printBlock ||
              `Dispenses a blueprint of revision ${ship.revision}, without lockbox contents. Costs the hull's storage fee. Build it at a shipyard fabricator and file it here to restore this slot.`
            }
            onClick={() => act('print_blueprint', { id: ship.id, pin })}
          >
            {ship.blueprintPrinted
              ? 'Blueprint printed'
              : `Print blueprint for ${credits(ship.blueprintFee)}`}
          </Button>
          <Button.Confirm
            fluid
            textAlign="center"
            icon="eraser"
            tooltip="Delete this record and free the slot. A printed blueprint still builds the hull, but filing it will need a free slot."
            onClick={() => act('clear_slot', { id: ship.id })}
          >
            Clear slot
          </Button.Confirm>
        </>
      ) : (
        <>
          <Button
            fluid
            textAlign="center"
            icon="plane-arrival"
            color="good"
            mb={0.5}
            disabled={!!reason && !isStaged}
            tooltip={
              reason || 'Choose coverage and confirm on the Landing Pad tab.'
            }
            onClick={() =>
              isStaged ? props.openPad() : props.onStage(ship.id)
            }
          >
            {isStaged ? 'Waiting on the pad tab' : 'Retrieve to pad'}
          </Button>
          {ship.status === 'FILED' && (
            <Button.Confirm
              fluid
              textAlign="center"
              icon="trash"
              disabled={!!scrapBlock}
              tooltip={
                scrapBlock ||
                'Pays a share of the hull and lockbox value, then frees the slot. This cannot be undone.'
              }
              onClick={() => act('decommission', { id: ship.id })}
            >
              Scrap for {credits(ship.scrapValue)}
            </Button.Confirm>
          )}
        </>
      )}
    </Section>
  );
};

const GarageTab = (props: {
  staged: Staged | null;
  onStage: (id: number) => void;
  openPad: () => void;
}) => {
  const { data } = useBackend<Data>();
  const [selectedId, setSelectedId] = useState<number | null>(null);

  if (!data.registryOnline) {
    return (
      <Section title="Garage" fill>
        <NoticeBox danger>Hangar registry offline.</NoticeBox>
      </Section>
    );
  }
  const selected =
    data.ships.find((ship) => ship.id === selectedId) || data.ships[0] || null;

  return (
    <Stack fill>
      <Stack.Item grow>
        <SlotGrid selectedId={selected?.id ?? null} onSelect={setSelectedId} />
      </Stack.Item>
      <Stack.Item basis="15rem">
        <ShipDetail
          ship={selected}
          staged={props.staged}
          onStage={props.onStage}
          openPad={props.openPad}
        />
      </Stack.Item>
    </Stack>
  );
};

const PadTabLabel = (props: { staged: Staged | null }) => {
  const { data } = useBackend<Data>();
  const occupant = data.zone.occupant;
  if (!data.zone.linked) {
    return (
      <>
        Landing Pad{' '}
        <Box inline color="average">
          <Icon name="unlink" />
        </Box>
      </>
    );
  }
  if (occupant) {
    return (
      <>
        Landing Pad{' '}
        <Box inline color="label">
          {occupant.name}
        </Box>
      </>
    );
  }
  if (props.staged) {
    return (
      <>
        Landing Pad{' '}
        <Box inline color="average">
          <Icon name="hourglass-half" /> retrieval pending
        </Box>
      </>
    );
  }
  return (
    <>
      Landing Pad{' '}
      <Box inline color="label">
        clear
      </Box>
    </>
  );
};

const RegistrarView = () => {
  const { data } = useBackend<Data>();
  const [tab, setTab] = useState<RegistrarTab>('PAD');
  const [staged, setStaged] = useState<Staged | null>(null);

  let body: ReactNode;
  switch (tab) {
    case 'PAD':
      body = (
        <PadTab
          staged={staged}
          setStaged={setStaged}
          openGarage={() => setTab('GARAGE')}
        />
      );
      break;
    case 'GARAGE':
      body = (
        <GarageTab
          staged={staged}
          onStage={(id) => {
            setStaged({ id, insured: null });
            setTab('PAD');
          }}
          openPad={() => setTab('PAD')}
        />
      );
      break;
    default: {
      const unhandled: never = tab;
      throw new Error(`unhandled tab ${unhandled}`);
    }
  }

  return (
    <Stack fill vertical>
      <Stack.Item>
        <HeaderView />
      </Stack.Item>
      <Stack.Item>
        <Tabs>
          <Tabs.Tab
            icon="plane-arrival"
            selected={tab === 'PAD'}
            onClick={() => setTab('PAD')}
          >
            <PadTabLabel staged={staged} />
          </Tabs.Tab>
          <Tabs.Tab
            icon="warehouse"
            selected={tab === 'GARAGE'}
            onClick={() => setTab('GARAGE')}
          >
            Garage{' '}
            <Box inline color="label">
              {data.slots.used} / {data.slots.total}
            </Box>
          </Tabs.Tab>
        </Tabs>
      </Stack.Item>
      <Stack.Item grow>{body}</Stack.Item>
    </Stack>
  );
};

export const ShipRegistrar = () => {
  const { data } = useBackend<Data>();

  return (
    <Window title="Vessel Registrar" width={760} height={640}>
      <Window.Content>
        {data.authenticated ? <RegistrarView /> : <LoginView />}
        <ShipyardBusy operation={data.busy} />
      </Window.Content>
    </Window>
  );
};
