// THIS IS A NOVA SECTOR UI FILE
import { type CSSProperties, useState } from 'react';
import {
  Box,
  Button,
  Collapsible,
  Divider,
  Icon,
  LabeledList,
  Modal,
  NoticeBox,
  Section,
  Stack,
  Table,
  Tabs,
  Tooltip,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

import { useBackend } from '../backend';
import { Window } from '../layouts';

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
  statusMessage: StatusMessage | null;
};

type GarageTab = 'all' | 'stored' | 'deployed' | 'lost';

const GARAGE_TABS: { id: GarageTab; label: string }[] = [
  { id: 'all', label: 'All' },
  { id: 'stored', label: 'Stored' },
  { id: 'deployed', label: 'Deployed' },
  { id: 'lost', label: 'Lost' },
];

const credits = (amount: number) =>
  `${Math.round(amount).toLocaleString('en-US')} cr`;

const plural = (count: number, word: string) =>
  `${count} ${word}${count === 1 ? '' : 's'}`;

const matchesTab = (ship: ShipEntry, tab: GarageTab) => {
  switch (tab) {
    case 'all':
      return true;
    case 'stored':
      return ship.status === 'FILED';
    case 'deployed':
      return ship.status === 'CHECKED_OUT';
    case 'lost':
      return ship.status === 'LOST';
    default: {
      const unhandled: never = tab;
      throw new Error(`unhandled garage tab ${unhandled}`);
    }
  }
};

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
    <Section
      title="Operator"
      buttons={
        <>
          <Button icon="rotate" onClick={() => act('refresh')}>
            Refresh
          </Button>
          <Button icon="sign-out-alt" onClick={() => act('logout')}>
            Log out
          </Button>
        </>
      }
    >
      <LabeledList>
        <LabeledList.Item label="Operator">
          {data.operatorName || 'Unidentified'}
        </LabeledList.Item>
        <LabeledList.Item label="Character">
          {data.characterName || 'Unknown'}
        </LabeledList.Item>
        <LabeledList.Item label="Ledger balance">
          {data.ledgerOnline && data.ledgerBalance !== null ? (
            <Box bold>{credits(data.ledgerBalance)}</Box>
          ) : (
            <Box color="average">
              <Icon name="exclamation-triangle" /> Ledger offline
            </Box>
          )}
        </LabeledList.Item>
      </LabeledList>
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
          <Icon name="users" /> Department, round-local
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
  if (!data.survey) {
    return 'Run a survey first so you can see what will be kept and what will be lost.';
  }
  if ((data.ledgerBalance ?? 0) < data.survey.quote.net) {
    return `Not enough credits. Filing costs ${credits(data.survey.quote.net)}.`;
  }
  return null;
};

const PadView = () => {
  const { act, data } = useBackend<Data>();
  const { zone, survey, refusal } = data;
  const occupant = zone.occupant;
  const surveyBlock = surveyDisabledReason(data);

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

  return (
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
              `Registry #${occupant.registryId}`
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
      {!!survey && <SurveySummary survey={survey} />}
      {!!occupant && <FileControls />}
      {!!survey && <SurveyDetails survey={survey} />}
    </Section>
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
    <Section title="Survey details" mt={1}>
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
    </Section>
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

const FileControls = () => {
  const { act, data } = useBackend<Data>();
  const reason = fileDisabledReason(data);
  const quote = data.survey?.quote;
  const balance = data.ledgerBalance ?? 0;

  return (
    <Section title="File to garage" mt={1}>
      {!!quote && (
        <LabeledList>
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
              <Tooltip content="Refunded insurance first pays this storage fee. Anything left over goes back to your ledger.">
                <Box inline color="good">
                  {credits(quote.insuranceRefund)}, netted against storage
                </Box>
              </Tooltip>
            </LabeledList.Item>
          )}
          {quote.net >= 0 ? (
            <LabeledList.Item label="Net charge">
              <Box inline bold>
                {credits(quote.net)}
              </Box>
            </LabeledList.Item>
          ) : (
            <LabeledList.Item label="Net credit" color="good">
              <Box inline bold>
                {credits(-quote.net)}
              </Box>
            </LabeledList.Item>
          )}
          {!!data.ledgerOnline && (
            <LabeledList.Item
              label="Balance after"
              color={balance < quote.net ? 'bad' : undefined}
            >
              {credits(balance - quote.net)}
            </LabeledList.Item>
          )}
        </LabeledList>
      )}
      <Box color="label" italic mt={quote ? 1 : 0} mb={1}>
        Filing removes the hull from the pad. Anything not kept is destroyed.
      </Box>
      <Button.Confirm
        fluid
        icon="archive"
        color="good"
        textAlign="center"
        disabled={!!reason}
        tooltip={reason}
        onClick={() => act('file')}
      >
        File ship
      </Button.Confirm>
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
          detail="File before round end or it is lost"
        />
      );
    case 'LOST':
      return (
        <StatusLine
          icon="skull"
          text="Lost"
          color="bad"
          detail="Deployed uninsured and never filed"
        />
      );
    default: {
      const unhandled: never = ship.status;
      throw new Error(`unhandled ship status ${unhandled}`);
    }
  }
};

const retrieveDisabledReason = (data: Data, ship: ShipEntry) => {
  if (ship.status === 'CHECKED_OUT') {
    return 'Already deployed this round.';
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

const GarageView = (props: { onRetrieve: (id: number) => void }) => {
  const { data } = useBackend<Data>();
  const [tab, setTab] = useState<GarageTab>('all');

  if (!data.registryOnline) {
    return (
      <Section title="Garage" fill>
        <NoticeBox danger>Hangar registry offline.</NoticeBox>
      </Section>
    );
  }
  if (!data.ships.length) {
    return (
      <Section title="Garage" fill>
        <NoticeBox info>
          Your garage is empty. Print a hull at the shipyard fabricator, land it
          on the pad, and file it here.
        </NoticeBox>
      </Section>
    );
  }
  const ships = data.ships.filter((ship) => matchesTab(ship, tab));

  return (
    <Section title="Garage" fill scrollable>
      <Tabs>
        {GARAGE_TABS.map((garageTab) => (
          <Tabs.Tab
            key={garageTab.id}
            selected={tab === garageTab.id}
            onClick={() => setTab(garageTab.id)}
          >
            {garageTab.label}{' '}
            <Box inline color="label">
              (
              {
                data.ships.filter((ship) => matchesTab(ship, garageTab.id))
                  .length
              }
              )
            </Box>
          </Tabs.Tab>
        ))}
      </Tabs>
      {ships.length ? (
        <Table>
          <Table.Row header>
            <Table.Cell>Vessel</Table.Cell>
            <Table.Cell collapsing>Tiles</Table.Cell>
            <Table.Cell collapsing>
              <Icon name="box" color="label" />
            </Table.Cell>
            <Table.Cell>Status</Table.Cell>
            <Table.Cell collapsing />
          </Table.Row>
          {ships.map((ship) => {
            const dim = ship.status === 'LOST' ? 'label' : undefined;
            const reason = retrieveDisabledReason(data, ship);
            return (
              <Table.Row key={ship.id}>
                <Table.Cell color={dim}>
                  <Box bold>{ship.name}</Box>
                  <Box color="label" fontSize="0.9em">
                    rev {ship.revision}
                  </Box>
                </Table.Cell>
                <Table.Cell collapsing color={dim}>
                  {ship.tiles}
                </Table.Cell>
                <Table.Cell collapsing color={dim} textAlign="center">
                  {ship.lockboxCount}
                </Table.Cell>
                <Table.Cell>
                  <StatusCell ship={ship} />
                </Table.Cell>
                <Table.Cell collapsing>
                  {ship.status !== 'LOST' && (
                    <Button
                      compact
                      icon="plane-arrival"
                      disabled={!!reason}
                      tooltip={reason}
                      onClick={() => props.onRetrieve(ship.id)}
                    >
                      Retrieve
                    </Button>
                  )}
                </Table.Cell>
              </Table.Row>
            );
          })}
        </Table>
      ) : (
        <Box color="label" italic mt={1}>
          Nothing here.
        </Box>
      )}
    </Section>
  );
};

const CoverageOption = (props: {
  ship: ShipEntry;
  insured: boolean;
  selected: boolean;
  onSelect: () => void;
}) => {
  const { data } = useBackend<Data>();
  const { ship, insured, selected, onSelect } = props;
  const fee = insured ? ship.quote.insured : ship.quote.uninsured;
  const balance = data.ledgerBalance ?? 0;
  const short = balance < fee;

  return (
    <Section
      fill
      title={
        <>
          <Icon
            name={insured ? 'shield-alt' : 'exclamation-triangle'}
            color={insured ? 'good' : 'average'}
          />{' '}
          {insured ? 'Insured' : 'Uninsured'}
        </>
      }
    >
      <LabeledList>
        <LabeledList.Item label="Fee">
          <Box inline bold>
            {credits(fee)}
          </Box>
        </LabeledList.Item>
        <LabeledList.Item
          label="Balance after"
          color={short ? 'bad' : undefined}
        >
          {credits(balance - fee)}
        </LabeledList.Item>
      </LabeledList>
      <Button
        fluid
        mt={1}
        textAlign="center"
        icon={selected ? 'check-square' : 'square-o'}
        selected={selected}
        disabled={short}
        tooltip={short ? `Not enough credits. You need ${credits(fee)}.` : null}
        onClick={onSelect}
      >
        {selected ? 'Selected' : 'Select'}
      </Button>
      <Box color="label" mt={1}>
        {insured
          ? `If the hull is lost, the garage keeps revision ${ship.revision}. Filing it again refunds the fee against storage.`
          : 'If the hull is lost, or not filed before round end, the ship is gone for good.'}
      </Box>
    </Section>
  );
};

const CheckoutModal = (props: { shipId: number; onClose: () => void }) => {
  const { act, data } = useBackend<Data>();
  const [insured, setInsured] = useState<boolean | null>(null);
  const ship = data.ships.find((entry) => entry.id === props.shipId);
  if (!ship) {
    return null;
  }
  const fee =
    insured === null
      ? null
      : insured
        ? ship.quote.insured
        : ship.quote.uninsured;

  return (
    <Modal width="36rem">
      <Section
        title={`Retrieve ${ship.name}`}
        buttons={
          <Button icon="times" color="transparent" onClick={props.onClose} />
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
            {ship.revision}, {ship.tiles} tiles, {ship.lockboxCount} lockbox
            items
          </LabeledList.Item>
          <LabeledList.Item label="Salvage estimate">
            {credits(ship.salvageEstimate)}
          </LabeledList.Item>
          <LabeledList.Item label="Ledger balance">
            {credits(data.ledgerBalance ?? 0)}
          </LabeledList.Item>
        </LabeledList>
        <Stack mt={1}>
          <Stack.Item grow>
            <CoverageOption
              ship={ship}
              insured
              selected={insured === true}
              onSelect={() => setInsured(true)}
            />
          </Stack.Item>
          <Stack.Item>
            <Divider vertical />
          </Stack.Item>
          <Stack.Item grow>
            <CoverageOption
              ship={ship}
              insured={false}
              selected={insured === false}
              onSelect={() => setInsured(false)}
            />
          </Stack.Item>
        </Stack>
        {insured === false && (
          <NoticeBox color="average" mt={1}>
            If {ship.name} is not filed before round end, its garage slot is
            emptied.
          </NoticeBox>
        )}
        <Stack mt={1}>
          <Stack.Item grow />
          <Stack.Item>
            <Button onClick={props.onClose}>Cancel</Button>
          </Stack.Item>
          <Stack.Item>
            <Button
              icon="plane-arrival"
              color="good"
              disabled={insured === null}
              tooltip={insured === null ? 'Choose coverage first.' : null}
              onClick={() => {
                act('retrieve', { id: ship.id, insured: insured ? 1 : 0 });
                props.onClose();
              }}
            >
              {fee === null ? 'Retrieve' : `Retrieve for ${credits(fee)}`}
            </Button>
          </Stack.Item>
        </Stack>
      </Section>
    </Modal>
  );
};

const RegistrarView = () => {
  const [retrieving, setRetrieving] = useState<number | null>(null);

  return (
    <>
      {retrieving !== null && (
        <CheckoutModal
          shipId={retrieving}
          onClose={() => setRetrieving(null)}
        />
      )}
      <Stack fill vertical>
        <Stack.Item>
          <HeaderView />
        </Stack.Item>
        <Stack.Item grow>
          <Stack fill>
            <Stack.Item basis="45%">
              <PadView />
            </Stack.Item>
            <Stack.Item grow>
              <GarageView onRetrieve={setRetrieving} />
            </Stack.Item>
          </Stack>
        </Stack.Item>
      </Stack>
    </>
  );
};

export const ShipRegistrar = () => {
  const { data } = useBackend<Data>();

  return (
    <Window title="Vessel Registrar" width={720} height={620}>
      <Window.Content>
        {data.authenticated ? <RegistrarView /> : <LoginView />}
      </Window.Content>
    </Window>
  );
};
