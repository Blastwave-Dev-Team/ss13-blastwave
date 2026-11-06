// THIS IS A NOVA SECTOR UI FILE
import { type CSSProperties, type ReactNode, useState } from 'react';
import {
  Box,
  Button,
  Divider,
  Icon,
  Input,
  LabeledList,
  Modal,
  NoticeBox,
  Section,
  Stack,
  Table,
  Tooltip,
} from 'tgui-core/components';
import { type BooleanLike, classes } from 'tgui-core/react';

import { useBackend } from '../backend';
import { Window } from '../layouts';
import { ShipyardBusy } from './common/ShipyardBusy';
import { ShipyardPin } from './common/ShipyardPin';

type Glyph = '.' | '#' | 'W' | 'A' | 'E' | 'I';

type Hull = {
  id: string;
  name: string;
  className: string;
  manufacturer: string;
  description: string;
  fittings: string[];
  width: number;
  height: number;
  tiles: number;
  cells: (Glyph | null)[];
  engines: { count: number; type: string };
  injectors: number;
  apcs: number;
  smes: number;
  airlocks: number;
  price: { hull: number; registration: number; insurance: number };
};

type Zone = {
  linked: BooleanLike;
  name: string | null;
  width: number;
  height: number;
  occupant: string | null;
};

type StatusMessage = { kind: 'good' | 'bad'; text: string };

type Data = {
  authenticated: BooleanLike;
  operatorName: string | null;
  characterName: string | null;
  affiliation: string | null;
  ledgerBalance: number | null;
  ledgerOnline: BooleanLike;
  registryOnline: BooleanLike;
  hulls: Hull[];
  garage: { used: number; total: number };
  zone: Zone;
  statusMessage: StatusMessage | null;
  busy: string | null;
};

type Delivery = 'PAD' | 'GARAGE';

type Page = 'HANGAR' | 'CATALOG';

type Focus =
  | { kind: 'hull' }
  | { kind: 'engines' }
  | { kind: 'injector' }
  | { kind: 'power' }
  | { kind: 'airlocks' }
  | { kind: 'fitting'; name: string };

type SortKey =
  | 'name'
  | 'className'
  | 'size'
  | 'tiles'
  | 'engines'
  | 'airlocks'
  | 'fit'
  | 'price';

type Sort = { key: SortKey; desc: boolean };

/** Client-side state shared by the pages, lifted to the root. */
type BrokerState = {
  selectedId: string | null;
  setSelectedId: (id: string) => void;
  delivery: Delivery;
  setDelivery: (delivery: Delivery) => void;
  name: string;
  setName: (name: string) => void;
  focus: Focus;
  setFocus: (focus: Focus) => void;
  showSystems: boolean;
  setShowSystems: (show: boolean) => void;
  page: Page;
  setPage: (page: Page) => void;
  filter: string;
  setFilter: (filter: string) => void;
  fitsOnly: boolean;
  setFitsOnly: (fitsOnly: boolean) => void;
  sort: Sort;
  setSort: (sort: Sort) => void;
  checkout: boolean;
  setCheckout: (open: boolean) => void;
};

const DELIVERIES: Delivery[] = ['PAD', 'GARAGE'];

const NAME_PATTERN = /^[A-Za-z0-9 '\-.]{3,32}$/;

const PIP_MAX = 8;

const credits = (amount: number) =>
  `${Math.round(amount).toLocaleString('en-US')} cr`;

const plural = (count: number, word: string) =>
  `${count} ${word}${count === 1 ? '' : 's'}`;

const nameProblem = (name: string) =>
  name && !NAME_PATTERN.test(name)
    ? 'Ship names are 3 to 32 letters, digits, spaces, apostrophes, dashes or dots.'
    : null;

const deliveryLabel = (delivery: Delivery) => {
  switch (delivery) {
    case 'PAD':
      return { letter: 'A', title: 'Land on pad', icon: 'plane-arrival' };
    case 'GARAGE':
      return { letter: 'B', title: 'Send to garage', icon: 'warehouse' };
    default: {
      const unhandled: never = delivery;
      throw new Error(`unhandled delivery ${unhandled}`);
    }
  }
};

const orderTotal = (hull: Hull, delivery: Delivery, insured: boolean) => {
  const base = hull.price.hull + hull.price.registration;
  switch (delivery) {
    case 'PAD':
      return base + (insured ? hull.price.insurance : 0);
    case 'GARAGE':
      return base;
    default: {
      const unhandled: never = delivery;
      throw new Error(`unhandled delivery ${unhandled}`);
    }
  }
};

// Matches the server: hulls are set down as drawn, never rotated.
const fitsPad = (hull: Hull, zone: Zone) =>
  hull.width <= zone.width && hull.height <= zone.height;

// An unlinked pad sorts and filters as "fits": nothing rules the hull out.
const fitRank = (hull: Hull, zone: Zone) =>
  !zone.linked || fitsPad(hull, zone) ? 1 : 0;

const sortValue = (hull: Hull, key: SortKey, zone: Zone): string | number => {
  switch (key) {
    case 'name':
      return hull.name.toLowerCase();
    case 'className':
      return hull.className.toLowerCase();
    case 'size':
      return hull.width * hull.height;
    case 'tiles':
      return hull.tiles;
    case 'engines':
      return hull.engines.count;
    case 'airlocks':
      return hull.airlocks;
    case 'fit':
      return fitRank(hull, zone);
    case 'price':
      return hull.price.hull;
    default: {
      const unhandled: never = key;
      throw new Error(`unhandled sort key ${unhandled}`);
    }
  }
};

/** Catalog order the player sees: sorted, ties broken by name. */
const sortedHulls = (hulls: Hull[], sort: Sort, zone: Zone) =>
  [...hulls].sort((a, b) => {
    const left = sortValue(a, sort.key, zone);
    const right = sortValue(b, sort.key, zone);
    const cmp =
      left < right ? -1 : left > right ? 1 : a.name.localeCompare(b.name);
    return sort.desc ? -cmp : cmp;
  });

const garageBlock = (data: Data) => {
  const { used, total } = data.garage;
  return used >= total
    ? `Garage full (${used} / ${total} slots). Scrap a ship or clear a lost one at a Vessel Registrar first.`
    : null;
};

/** Why this delivery cannot work for this hull right now, money and naming aside. */
const deliveryBlock = (data: Data, hull: Hull, delivery: Delivery) => {
  if (!data.registryOnline) {
    return 'Hangar registry offline. Purchased hulls have to be registered.';
  }
  const full = garageBlock(data);
  if (full) {
    return full;
  }
  switch (delivery) {
    case 'PAD':
      if (!data.zone.linked) {
        return 'No landing pad linked. Use a multitool on a landing controller, then on this console.';
      }
      if (data.zone.occupant) {
        return `${data.zone.name} is occupied by ${data.zone.occupant}. Clear the pad first.`;
      }
      if (!fitsPad(hull, data.zone)) {
        return `${hull.width} x ${hull.height} does not fit ${data.zone.name} (${data.zone.width} x ${data.zone.height}).`;
      }
      return null;
    case 'GARAGE':
      return null;
    default: {
      const unhandled: never = delivery;
      throw new Error(`unhandled delivery ${unhandled}`);
    }
  }
};

const purchaseBlock = (
  data: Data,
  hull: Hull,
  delivery: Delivery,
  name: string,
  insured: boolean,
) => {
  if (!data.ledgerOnline) {
    return 'Ledger offline. Nothing can be charged.';
  }
  const block = deliveryBlock(data, hull, delivery);
  if (block) {
    return block;
  }
  const bad = nameProblem(name.trim());
  if (bad) {
    return bad;
  }
  const total = orderTotal(hull, delivery, insured);
  if ((data.ledgerBalance ?? 0) < total) {
    return `Not enough credits. This order costs ${credits(total)}.`;
  }
  return null;
};

const focusGlyph = (focus: Focus): Glyph | null => {
  switch (focus.kind) {
    case 'engines':
      return 'E';
    case 'injector':
      return 'I';
    case 'airlocks':
      return 'A';
    case 'hull':
    case 'power':
    case 'fitting':
      return null;
    default: {
      const unhandled: never = focus;
      throw new Error(`unhandled focus ${JSON.stringify(unhandled)}`);
    }
  }
};

const sameFocus = (a: Focus, b: Focus) =>
  a.kind === b.kind &&
  (a.kind !== 'fitting' || (b.kind === 'fitting' && a.name === b.name));

const glyphClass = (glyph: Glyph) => {
  switch (glyph) {
    case '.':
      return 'floor';
    case '#':
      return 'wall';
    case 'W':
      return 'window';
    case 'A':
      return 'airlock';
    case 'E':
      return 'engine';
    case 'I':
      return 'injector';
    default: {
      const unhandled: never = glyph;
      throw new Error(`unhandled glyph ${unhandled}`);
    }
  }
};

const GLYPH_NAMES: Record<Glyph, string> = {
  '.': 'Deck',
  '#': 'Hull wall',
  W: 'Window',
  A: 'Airlock',
  E: 'Engine',
  I: 'Fuel injector',
};

const MARKER_KINDS: Partial<Record<Glyph, string>> = {
  E: 'engine',
  I: 'injector',
  A: 'airlock',
};

const LoginView = () => {
  const { act, data } = useBackend<Data>();

  return (
    <Stack fill vertical>
      <Stack.Item grow />
      <Stack.Item align="center">
        <Icon name="space-shuttle" size={9} color="good" />
      </Stack.Item>
      <Stack.Item align="center">
        <Box color="good" fontSize="18px" bold mt={2}>
          Nanotrasen Vessel Broker
        </Box>
      </Stack.Item>
      <Stack.Item align="center">
        <Box color="label" italic>
          Swipe an ID to browse hulls and buy one against your ledger.
        </Box>
      </Stack.Item>
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

const BalanceBox = () => {
  const { data } = useBackend<Data>();
  return (
    <Box textAlign="right">
      <Box color="label" fontSize="0.9em">
        {data.characterName || data.operatorName}
        {!!data.affiliation && ` · ${data.affiliation}`}
      </Box>
      {data.ledgerOnline && data.ledgerBalance !== null ? (
        <Box bold>{credits(data.ledgerBalance)}</Box>
      ) : (
        <Box color="average">
          <Icon name="exclamation-triangle" /> Ledger offline
        </Box>
      )}
    </Box>
  );
};

const HeaderBar = (props: { hull: Hull; state: BrokerState }) => {
  const { act, data } = useBackend<Data>();
  const { hull, state } = props;
  const block = purchaseBlock(data, hull, state.delivery, state.name, false);
  // The arrows walk the catalog's current order, so both pages agree on "next".
  const order = sortedHulls(data.hulls, state.sort, data.zone);
  const at = order.findIndex((entry) => entry.id === hull.id);
  const step = (delta: number) =>
    order[(at + delta + order.length) % order.length].id;
  const nameBad = nameProblem(state.name.trim());

  return (
    <Section>
      <Stack align="center">
        <Stack.Item basis="16rem">
          <Box color="label" fontSize="0.9em">
            Vessel name
          </Box>
          <Input
            fluid
            value={state.name}
            placeholder={hull.name}
            maxLength={32}
            onChange={state.setName}
          />
          {!!nameBad && (
            <Box color="bad" fontSize="0.85em">
              <Icon name="exclamation-circle" /> {nameBad}
            </Box>
          )}
        </Stack.Item>
        <Stack.Item ml={1}>
          <Button
            icon="chevron-left"
            tooltip="Previous hull"
            onClick={() => state.setSelectedId(step(-1))}
          />
          <Button
            icon="list"
            tooltip="Browse, filter and sort every hull"
            onClick={() => state.setPage('CATALOG')}
          >
            Catalog {at + 1} / {order.length}
          </Button>
          <Button
            icon="chevron-right"
            tooltip="Next hull"
            onClick={() => state.setSelectedId(step(1))}
          />
        </Stack.Item>
        <Stack.Item grow />
        <Stack.Item>
          <BalanceBox />
        </Stack.Item>
        <Stack.Item>
          <Button
            icon="sign-out-alt"
            color="transparent"
            tooltip="Log out"
            onClick={() => act('logout')}
          />
        </Stack.Item>
        <Stack.Item ml={1}>
          <Button
            className="ShipBroker__buy"
            icon="shopping-cart"
            color="good"
            disabled={!!block}
            tooltip={block}
            onClick={() => state.setCheckout(true)}
          >
            PURCHASE
          </Button>
        </Stack.Item>
      </Stack>
      {!!data.statusMessage && <StatusNotice message={data.statusMessage} />}
    </Section>
  );
};

const Requirement = (props: { ok: boolean; icon: string; text: string }) => (
  <Box mb={0.25} color={props.ok ? undefined : 'label'}>
    <Icon
      name={props.ok ? props.icon : 'lock'}
      color={props.ok ? 'good' : 'bad'}
    />{' '}
    {props.text}
  </Box>
);

const HullPanel = (props: { hull: Hull; state: BrokerState }) => {
  const { data } = useBackend<Data>();
  const { hull, state } = props;
  const zone = data.zone;
  const basePrice = hull.price.hull + hull.price.registration;

  return (
    <Stack fill vertical>
      <Stack.Item>
        <Section title="Delivery">
          <div className="ShipBroker__delivery">
            {DELIVERIES.map((delivery) => {
              const label = deliveryLabel(delivery);
              const block = deliveryBlock(data, hull, delivery);
              return (
                <Button
                  key={delivery}
                  fluid
                  mb={0.5}
                  selected={state.delivery === delivery}
                  color={block ? 'transparent' : undefined}
                  tooltip={block}
                  onClick={() => state.setDelivery(delivery)}
                >
                  <span className="ShipBroker__letter">{label.letter}</span>
                  <Icon name={label.icon} /> {label.title}
                  <Box color="label" fontSize="0.9em" ml={3.3}>
                    {block ? (
                      <Box inline color="bad">
                        <Icon name="ban" /> Unavailable
                      </Box>
                    ) : (
                      credits(basePrice)
                    )}
                  </Box>
                </Button>
              );
            })}
          </div>
        </Section>
      </Stack.Item>
      <Stack.Item>
        <Section title="Landing pad">
          {zone.linked ? (
            <>
              <Box>
                {zone.name}{' '}
                <Box inline color="label">
                  {zone.width} x {zone.height}
                </Box>
              </Box>
              {zone.occupant ? (
                <Box color="average">
                  <Icon name="plane" /> Occupied by {zone.occupant}
                </Box>
              ) : (
                <Box color="good">
                  <Icon name="check" /> Clear
                </Box>
              )}
            </>
          ) : (
            <Box color="average">
              <Icon name="unlink" /> No pad linked
            </Box>
          )}
        </Section>
      </Stack.Item>
      <Stack.Item grow>
        <Section title="Requirements" fill>
          <Requirement
            ok={!!data.ledgerOnline}
            icon="wallet"
            text={data.ledgerOnline ? 'Ledger online' : 'Ledger offline'}
          />
          <Requirement
            ok={!!data.registryOnline}
            icon="database"
            text={data.registryOnline ? 'Registry online' : 'Registry offline'}
          />
          <Requirement
            ok={!garageBlock(data)}
            icon="warehouse"
            text={`Garage slot free (${data.garage.used} / ${data.garage.total} used)`}
          />
          <Requirement
            ok={!!zone.linked}
            icon="link"
            text={zone.linked ? 'Pad linked' : 'No pad linked'}
          />
          <Requirement
            ok={!zone.linked || fitsPad(hull, zone)}
            icon="ruler-combined"
            text={zone.linked ? `Fits ${zone.name}` : 'Pad fit unknown'}
          />
        </Section>
      </Stack.Item>
    </Stack>
  );
};

const SchematicPreview = (props: { hull: Hull }) => {
  const { hull } = props;
  return (
    <div className="ShipBroker__grid">
      {hull.cells.map((glyph, index) => {
        if (!glyph) {
          return <div key={index} />;
        }
        const x = (index % hull.width) + 1;
        const y = Math.floor(index / hull.width) + 1;
        return (
          <div
            key={index}
            className={`ShipBroker__tile--${glyphClass(glyph)}`}
            title={`Tile ${x}, ${y}\n${GLYPH_NAMES[glyph]}`}
          />
        );
      })}
    </div>
  );
};

const SystemMarkers = (props: { hull: Hull; state: BrokerState }) => {
  const { hull, state } = props;
  const focused = focusGlyph(state.focus);
  if (!state.showSystems && !focused) {
    return null;
  }
  return (
    <>
      {hull.cells.map((glyph, index) => {
        const kind = glyph && MARKER_KINDS[glyph];
        if (!kind || (!state.showSystems && glyph !== focused)) {
          return null;
        }
        const x = index % hull.width;
        const y = Math.floor(index / hull.width);
        return (
          <div
            key={index}
            className={classes([
              'ShipBroker__marker',
              `ShipBroker__marker--${kind}`,
              glyph === focused && 'ShipBroker__marker--focus',
            ])}
            style={{
              left: `${(x / hull.width) * 100}%`,
              top: `${(y / hull.height) * 100}%`,
              width: `${100 / hull.width}%`,
              height: `${100 / hull.height}%`,
            }}
          />
        );
      })}
    </>
  );
};

type SystemGroup = {
  focus: Focus;
  icon: string;
  color: string;
  label: string;
  count: number;
};

const SystemPips = (props: { hull: Hull; state: BrokerState }) => {
  const { hull, state } = props;
  const groups: SystemGroup[] = [
    {
      focus: { kind: 'engines' },
      icon: 'fire',
      color: 'orange',
      label: 'Engines',
      count: hull.engines.count,
    },
    {
      focus: { kind: 'injector' },
      icon: 'burn',
      color: 'teal',
      label: 'Injector',
      count: hull.injectors,
    },
    {
      focus: { kind: 'power' },
      icon: 'bolt',
      color: 'yellow',
      label: 'Power',
      count: hull.apcs + hull.smes,
    },
    {
      focus: { kind: 'airlocks' },
      icon: 'door-open',
      color: 'average',
      label: 'Airlocks',
      count: hull.airlocks,
    },
  ];
  return (
    <div className="ShipBroker__systems">
      {groups.map((group) => {
        const selected = sameFocus(state.focus, group.focus);
        const pipCount = Math.min(PIP_MAX, Math.max(group.count, 1));
        return (
          <Tooltip key={group.label} content={`${group.label}: ${group.count}`}>
            <div
              className={classes([
                'ShipBroker__system',
                selected && 'ShipBroker__system--selected',
              ])}
              onClick={() =>
                state.setFocus(selected ? { kind: 'hull' } : group.focus)
              }
            >
              {Array.from({ length: pipCount }, (_, index) => (
                <div
                  key={index}
                  className={classes([
                    'ShipBroker__pip',
                    pipCount - 1 - index >= group.count &&
                      'ShipBroker__pip--off',
                  ])}
                />
              ))}
              <Box mt={0.25}>
                <Icon name={group.icon} color={group.color} />
              </Box>
              <Box fontSize="0.85em" color="label">
                {group.count > PIP_MAX ? `${PIP_MAX}+` : group.count}
              </Box>
            </div>
          </Tooltip>
        );
      })}
    </div>
  );
};

/** The hangar bay. Compact drops the interactive systems for the catalog preview. */
const Hangar = (props: {
  hull: Hull;
  state: BrokerState;
  compact?: boolean;
}) => {
  const { hull, state, compact } = props;

  return (
    <div className="ShipBroker__hangar">
      <div className="ShipBroker__stage">
        {!compact && (
          <div className="ShipBroker__nose">
            <Button
              compact
              color="transparent"
              icon={state.showSystems ? 'eye-slash' : 'crosshairs'}
              onClick={() => state.setShowSystems(!state.showSystems)}
            >
              {state.showSystems ? 'Hide systems' : 'Show systems'}
            </Button>
          </div>
        )}
        <div
          className="ShipBroker__ship"
          style={{ '--w': hull.width, '--h': hull.height } as CSSProperties}
        >
          <SchematicPreview hull={hull} />
          {!compact && <SystemMarkers hull={hull} state={state} />}
        </div>
      </div>
      {!compact && (
        <>
          <Box textAlign="center" mb={0.25}>
            <Box inline bold fontSize="1.2em">
              {hull.name}
            </Box>{' '}
            <Box inline color="label">
              {hull.className} · {hull.manufacturer}
            </Box>
          </Box>
          <SystemPips hull={hull} state={state} />
        </>
      )}
    </div>
  );
};

const PadFit = (props: { hull: Hull }) => {
  const { data } = useBackend<Data>();
  const { zone } = data;
  if (!zone.linked) {
    return (
      <Box inline color="label">
        No pad linked
      </Box>
    );
  }
  return fitsPad(props.hull, zone) ? (
    <Box inline color="good">
      Fits {zone.name}
    </Box>
  ) : (
    <Box inline color="bad">
      Too large for {zone.name}
    </Box>
  );
};

const DetailPanel = (props: { hull: Hull; state: BrokerState }) => {
  const { hull, state } = props;
  const { focus } = state;
  let title: string;
  let body: ReactNode;
  switch (focus.kind) {
    case 'hull':
      title = hull.name;
      body = (
        <>
          <LabeledList>
            <LabeledList.Item label="Class">{hull.className}</LabeledList.Item>
            <LabeledList.Item label="Maker">
              {hull.manufacturer}
            </LabeledList.Item>
            <LabeledList.Item label="Footprint">
              {hull.width} x {hull.height}
            </LabeledList.Item>
            <LabeledList.Item label="Hull tiles">{hull.tiles}</LabeledList.Item>
            <LabeledList.Item label="Engines">
              {hull.engines.count} x {hull.engines.type}
            </LabeledList.Item>
            <LabeledList.Item label="Airlocks">
              {hull.airlocks}
            </LabeledList.Item>
            <LabeledList.Item label="Pad">
              <PadFit hull={hull} />
            </LabeledList.Item>
          </LabeledList>
          <Box mt={1} color="label">
            {hull.description}
          </Box>
        </>
      );
      break;
    case 'engines':
      title = `${hull.engines.type} x ${hull.engines.count}`;
      body = (
        <>
          <LabeledList>
            <LabeledList.Item label="Count">
              {hull.engines.count}
            </LabeledList.Item>
            <LabeledList.Item label="Feed">
              Piped from the fuel injector
            </LabeledList.Item>
          </LabeledList>
          <Box mt={1} color="label">
            More engines on the same injector means more thrust, and a faster
            drain on the chamber.
          </Box>
        </>
      );
      break;
    case 'injector':
      title = 'Fuel injector';
      body = (
        <>
          <LabeledList>
            <LabeledList.Item label="Count">{hull.injectors}</LabeledList.Item>
            <LabeledList.Item label="Chamber">Delivered empty</LabeledList.Item>
            <LabeledList.Item label="Feeds">
              {plural(hull.engines.count, 'engine')}
            </LabeledList.Item>
          </LabeledList>
          <Box mt={1} color="label">
            Processes piped or tanked propellant for every linked thruster.
            Delivered hulls arrive with an empty chamber: fuel before you fly.
          </Box>
        </>
      );
      break;
    case 'power':
      title = 'Power';
      body = (
        <LabeledList>
          <LabeledList.Item label="APCs">{hull.apcs}</LabeledList.Item>
          <LabeledList.Item label="SMES">{hull.smes}</LabeledList.Item>
        </LabeledList>
      );
      break;
    case 'airlocks':
      title = 'Airlocks';
      body = (
        <LabeledList>
          <LabeledList.Item label="Count">{hull.airlocks}</LabeledList.Item>
        </LabeledList>
      );
      break;
    case 'fitting':
      title = focus.name;
      body = (
        <Box color="label">
          Installed at purchase and included in the hull price.
        </Box>
      );
      break;
    default: {
      const unhandled: never = focus;
      throw new Error(`unhandled focus ${JSON.stringify(unhandled)}`);
    }
  }

  return (
    <Section
      title={title}
      fill
      scrollable
      buttons={
        focus.kind !== 'hull' && (
          <Button
            icon="arrow-left"
            compact
            color="transparent"
            tooltip="Back to hull overview"
            onClick={() => state.setFocus({ kind: 'hull' })}
          />
        )
      }
    >
      {body}
    </Section>
  );
};

type SlotCard = {
  focus: Focus;
  icon: string;
  color: string;
  label: string;
  count?: number;
};

const SlotRow = (props: {
  title: string;
  cards: SlotCard[];
  slots: number;
  state: BrokerState;
}) => {
  const { cards, slots, state } = props;
  return (
    <Section title={props.title} fill>
      <div className="ShipBroker__slots">
        {cards.map((card) => (
          <div
            key={card.label}
            className={classes([
              'ShipBroker__card',
              sameFocus(state.focus, card.focus) &&
                'ShipBroker__card--selected',
            ])}
            onClick={() => state.setFocus(card.focus)}
          >
            <Icon name={card.icon} color={card.color} size={1.3} />
            <div>
              <Box fontSize="0.9em">{card.label}</Box>
              {card.count !== undefined && (
                <Box className="ShipBroker__count">x{card.count}</Box>
              )}
            </div>
          </div>
        ))}
        {Array.from({ length: Math.max(0, slots - cards.length) }, (_, i) => (
          <div key={i} className="ShipBroker__card ShipBroker__card--empty">
            Not installed
          </div>
        ))}
      </div>
    </Section>
  );
};

const SlotBar = (props: { hull: Hull; state: BrokerState }) => {
  const { hull, state } = props;
  return (
    <Stack fill>
      <Stack.Item grow minWidth={0}>
        <SlotRow
          title="Propulsion"
          slots={2}
          state={state}
          cards={[
            {
              focus: { kind: 'engines' },
              icon: 'fire',
              color: 'orange',
              label: hull.engines.type,
              count: hull.engines.count,
            },
            {
              focus: { kind: 'injector' },
              icon: 'burn',
              color: 'teal',
              label: 'Fuel injector',
              count: hull.injectors,
            },
          ]}
        />
      </Stack.Item>
      <Stack.Item grow minWidth={0}>
        <SlotRow
          title="Power"
          slots={2}
          state={state}
          cards={[
            {
              focus: { kind: 'power' },
              icon: 'plug',
              color: 'yellow',
              label: 'APC',
              count: hull.apcs,
            },
            {
              focus: { kind: 'power' },
              icon: 'car-battery',
              color: 'yellow',
              label: 'SMES',
              count: hull.smes,
            },
          ]}
        />
      </Stack.Item>
      <Stack.Item grow={2} minWidth={0}>
        <SlotRow
          title="Fittings"
          slots={4}
          state={state}
          cards={hull.fittings.map((fitting) => ({
            focus: { kind: 'fitting', name: fitting },
            icon: 'cube',
            color: 'good',
            label: fitting,
          }))}
        />
      </Stack.Item>
    </Stack>
  );
};

const HangarPage = (props: { hull: Hull; state: BrokerState }) => {
  const { hull, state } = props;
  return (
    <Stack fill vertical>
      <Stack.Item>
        <HeaderBar hull={hull} state={state} />
      </Stack.Item>
      <Stack.Item grow>
        <Stack fill>
          <Stack.Item basis="15rem">
            <HullPanel hull={hull} state={state} />
          </Stack.Item>
          <Stack.Item grow minWidth={0}>
            <Hangar hull={hull} state={state} />
          </Stack.Item>
          <Stack.Item basis="17rem">
            <DetailPanel hull={hull} state={state} />
          </Stack.Item>
        </Stack>
      </Stack.Item>
      <Stack.Item basis="6.5rem">
        <SlotBar hull={hull} state={state} />
      </Stack.Item>
    </Stack>
  );
};

type CatalogColumn = {
  key: SortKey;
  label: ReactNode;
  tip?: string;
  collapsing?: boolean;
  align?: 'left' | 'center' | 'right';
};

const CATALOG_COLUMNS: CatalogColumn[] = [
  { key: 'name', label: 'Hull' },
  { key: 'className', label: 'Class' },
  {
    key: 'size',
    label: 'Size',
    tip: 'Footprint, sorted by area',
    collapsing: true,
  },
  { key: 'tiles', label: 'Tiles', collapsing: true, align: 'right' },
  {
    key: 'engines',
    label: <Icon name="fire" />,
    tip: 'Engines',
    collapsing: true,
    align: 'center',
  },
  {
    key: 'airlocks',
    label: <Icon name="door-open" />,
    tip: 'Airlocks',
    collapsing: true,
    align: 'center',
  },
  {
    key: 'fit',
    label: 'Pad',
    tip: 'Fits the linked landing pad',
    collapsing: true,
    align: 'center',
  },
  { key: 'price', label: 'Price', collapsing: true, align: 'right' },
];

const CatalogCell = (props: { hull: Hull; column: SortKey }) => {
  const { data } = useBackend<Data>();
  const { hull, column } = props;
  switch (column) {
    case 'name':
      return (
        <>
          <Box bold>{hull.name}</Box>
          <Box color="label" fontSize="0.85em">
            {hull.manufacturer}
          </Box>
        </>
      );
    case 'className':
      return <>{hull.className}</>;
    case 'size':
      return (
        <>
          {hull.width} x {hull.height}
        </>
      );
    case 'tiles':
      return <>{hull.tiles}</>;
    case 'engines':
      return <>{hull.engines.count}</>;
    case 'airlocks':
      return <>{hull.airlocks}</>;
    case 'fit':
      if (!data.zone.linked) {
        return <Box color="label">-</Box>;
      }
      return fitsPad(hull, data.zone) ? (
        <Icon name="check" color="good" />
      ) : (
        <Icon name="times" color="bad" />
      );
    case 'price':
      return <>{credits(hull.price.hull)}</>;
    default: {
      const unhandled: never = column;
      throw new Error(`unhandled column ${unhandled}`);
    }
  }
};

const SortIcon = (props: { sort: Sort; column: SortKey }) => {
  const { sort, column } = props;
  if (sort.key !== column) {
    return <Icon name="sort" color="label" />;
  }
  return <Icon name={sort.desc ? 'sort-down' : 'sort-up'} />;
};

const CatalogPage = (props: { hull: Hull; state: BrokerState }) => {
  const { data } = useBackend<Data>();
  const { hull, state } = props;
  const needle = state.filter.trim().toLowerCase();
  const rows = sortedHulls(data.hulls, state.sort, data.zone).filter(
    (entry) =>
      (!state.fitsOnly || fitRank(entry, data.zone)) &&
      (!needle ||
        [entry.name, entry.manufacturer, entry.className].some((text) =>
          text.toLowerCase().includes(needle),
        )),
  );
  const hidden = data.hulls.length - rows.length;

  return (
    <Stack fill vertical>
      <Stack.Item>
        <Section>
          <Stack align="center">
            <Stack.Item>
              <Button icon="arrow-left" onClick={() => state.setPage('HANGAR')}>
                Go Back
              </Button>
            </Stack.Item>
            <Stack.Item grow ml={1}>
              <Input
                fluid
                value={state.filter}
                placeholder="Filter by name, maker or class"
                onChange={state.setFilter}
              />
            </Stack.Item>
            <Stack.Item>
              <Button
                icon={state.fitsOnly ? 'check-square' : 'square-o'}
                selected={state.fitsOnly}
                disabled={!data.zone.linked}
                tooltip={
                  data.zone.linked
                    ? `Only hulls that fit ${data.zone.name}`
                    : 'No landing pad linked'
                }
                onClick={() => state.setFitsOnly(!state.fitsOnly)}
              >
                Fits pad
              </Button>
            </Stack.Item>
            <Stack.Item ml={1}>
              <BalanceBox />
            </Stack.Item>
          </Stack>
        </Section>
      </Stack.Item>
      <Stack.Item grow>
        <Stack fill>
          <Stack.Item grow={3} minWidth={0}>
            <Section
              title={
                <>
                  Hull catalog{' '}
                  <Box inline color="label">
                    {hidden
                      ? `${rows.length} of ${data.hulls.length}`
                      : rows.length}
                  </Box>
                </>
              }
              fill
              scrollable
            >
              {rows.length ? (
                <Table>
                  <Table.Row header>
                    {CATALOG_COLUMNS.map((column) => (
                      <Table.Cell
                        key={column.key}
                        header
                        collapsing={column.collapsing}
                        textAlign={column.align}
                        className="ShipBroker__sort"
                        onClick={() =>
                          state.setSort({
                            key: column.key,
                            desc:
                              state.sort.key === column.key
                                ? !state.sort.desc
                                : false,
                          })
                        }
                      >
                        <Tooltip
                          content={
                            column.tip
                              ? `${column.tip}. Click to sort.`
                              : 'Click to sort.'
                          }
                        >
                          <span>
                            {column.label}{' '}
                            <SortIcon sort={state.sort} column={column.key} />
                          </span>
                        </Tooltip>
                      </Table.Cell>
                    ))}
                  </Table.Row>
                  {rows.map((entry) => (
                    <Table.Row
                      key={entry.id}
                      className={classes([
                        'ShipBroker__row',
                        entry.id === hull.id && 'ShipBroker__row--selected',
                      ])}
                      onClick={() => state.setSelectedId(entry.id)}
                    >
                      {CATALOG_COLUMNS.map((column) => (
                        <Table.Cell
                          key={column.key}
                          collapsing={column.collapsing}
                          textAlign={column.align}
                          nowrap={
                            column.key === 'size' || column.key === 'price'
                          }
                        >
                          <CatalogCell hull={entry} column={column.key} />
                        </Table.Cell>
                      ))}
                    </Table.Row>
                  ))}
                </Table>
              ) : (
                <NoticeBox info>
                  No hulls match.{' '}
                  <Button
                    compact
                    onClick={() => {
                      state.setFilter('');
                      state.setFitsOnly(false);
                    }}
                  >
                    Clear filters
                  </Button>
                </NoticeBox>
              )}
            </Section>
          </Stack.Item>
          <Stack.Item grow={2} minWidth={0}>
            <Stack fill vertical>
              <Stack.Item grow>
                <Hangar hull={hull} state={state} compact />
              </Stack.Item>
              <Stack.Item basis="11rem">
                <Section
                  title={hull.name}
                  fill
                  scrollable
                  buttons={
                    <Button
                      icon="warehouse"
                      color="good"
                      onClick={() => state.setPage('HANGAR')}
                    >
                      View in hangar
                    </Button>
                  }
                >
                  <LabeledList>
                    <LabeledList.Item label="Class">
                      {hull.className}
                    </LabeledList.Item>
                    <LabeledList.Item label="Maker">
                      {hull.manufacturer}
                    </LabeledList.Item>
                    <LabeledList.Item label="Engines">
                      {hull.engines.count} x {hull.engines.type}
                    </LabeledList.Item>
                    <LabeledList.Item label="Price">
                      {credits(hull.price.hull)}
                    </LabeledList.Item>
                  </LabeledList>
                  <Box mt={1} color="label">
                    {hull.description}
                  </Box>
                </Section>
              </Stack.Item>
            </Stack>
          </Stack.Item>
        </Stack>
      </Stack.Item>
    </Stack>
  );
};

const CoverageOption = (props: {
  hull: Hull;
  name: string;
  insured: boolean;
  selected: boolean;
  onSelect: () => void;
}) => {
  const { data } = useBackend<Data>();
  const { hull, name, insured, selected, onSelect } = props;
  const balance = data.ledgerBalance ?? 0;
  const total = orderTotal(hull, 'PAD', insured);
  const short = balance < total;

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
        <LabeledList.Item label="Total">
          <Box inline bold>
            {credits(total)}
          </Box>
        </LabeledList.Item>
        <LabeledList.Item
          label="Balance after"
          color={short ? 'bad' : undefined}
        >
          {credits(balance - total)}
        </LabeledList.Item>
      </LabeledList>
      <Button
        fluid
        mt={1}
        textAlign="center"
        icon={selected ? 'check-square' : 'square-o'}
        selected={selected}
        disabled={short}
        tooltip={
          short ? `Not enough credits. You need ${credits(total)}.` : null
        }
        onClick={onSelect}
      >
        {selected ? 'Selected' : 'Select'}
      </Button>
      <Box color="label" mt={1}>
        {insured
          ? `If ${name} is lost, the garage restores it as delivered. Costs ${credits(hull.price.insurance)} on top.`
          : 'If the hull is lost, or not filed at a registrar before the shift ends, it is gone for good.'}
      </Box>
    </Section>
  );
};

const CheckoutModal = (props: { hull: Hull; state: BrokerState }) => {
  const { act, data } = useBackend<Data>();
  const { hull, state } = props;
  const [pick, setPick] = useState<boolean | null>(null);
  const [pin, setPin] = useState('');
  const { delivery } = state;
  const name = state.name.trim() || hull.name;
  const label = deliveryLabel(delivery);
  const needsCoverage = delivery === 'PAD';
  const insured = needsCoverage && pick === true;
  const ready = !needsCoverage || pick !== null;
  const total = ready ? orderTotal(hull, delivery, insured) : null;
  const block = ready
    ? purchaseBlock(data, hull, delivery, state.name, insured) ||
      (pin.length < 1 ? 'Enter your ledger PIN to purchase.' : null)
    : 'Choose coverage first.';
  let outcome: string;
  switch (delivery) {
    case 'PAD':
      outcome = `${name} lands on ${data.zone.name} as soon as you confirm, registered to you.`;
      break;
    case 'GARAGE':
      outcome = `${name} is filed straight to your garage as revision 1. Retrieve it at any Vessel Registrar, and choose coverage then.`;
      break;
    default: {
      const unhandled: never = delivery;
      throw new Error(`unhandled delivery ${unhandled}`);
    }
  }
  const close = () => state.setCheckout(false);

  return (
    <Modal width="38rem">
      <Section
        title={`Purchase ${name}`}
        buttons={<Button icon="times" color="transparent" onClick={close} />}
      >
        <LabeledList>
          <LabeledList.Item label="Hull">
            {hull.name}{' '}
            <Box inline color="label">
              {hull.width} x {hull.height}, {hull.tiles} tiles
            </Box>
          </LabeledList.Item>
          <LabeledList.Item label="Delivery">
            <Icon name={label.icon} /> {label.title}
          </LabeledList.Item>
          <LabeledList.Item label="Garage slot">
            Takes 1 of {data.garage.total - data.garage.used} free (
            {data.garage.used} / {data.garage.total} used)
          </LabeledList.Item>
          <LabeledList.Item label="Hull">
            {credits(hull.price.hull)}
          </LabeledList.Item>
          <LabeledList.Item label="Registration">
            {credits(hull.price.registration)}
          </LabeledList.Item>
          {!needsCoverage && total !== null && (
            <LabeledList.Item label="Total">
              <Box inline bold>
                {credits(total)}
              </Box>
            </LabeledList.Item>
          )}
          <LabeledList.Item label="Ledger balance">
            {credits(data.ledgerBalance ?? 0)}
          </LabeledList.Item>
        </LabeledList>
        <Box color="label" mt={1}>
          {outcome}
        </Box>
        {needsCoverage && (
          <Stack mt={1}>
            <Stack.Item grow>
              <CoverageOption
                hull={hull}
                name={name}
                insured
                selected={pick === true}
                onSelect={() => setPick(true)}
              />
            </Stack.Item>
            <Stack.Item>
              <Divider vertical />
            </Stack.Item>
            <Stack.Item grow>
              <CoverageOption
                hull={hull}
                name={name}
                insured={false}
                selected={pick === false}
                onSelect={() => setPick(false)}
              />
            </Stack.Item>
          </Stack>
        )}
        <LabeledList>
          <ShipyardPin value={pin} onChange={setPin} />
        </LabeledList>
        <Stack mt={1}>
          <Stack.Item grow />
          <Stack.Item>
            <Button onClick={close}>Cancel</Button>
          </Stack.Item>
          <Stack.Item>
            <Button.Confirm
              icon="shopping-cart"
              color="good"
              disabled={!!block}
              tooltip={block}
              onClick={() => {
                act('purchase', {
                  id: hull.id,
                  delivery,
                  insured: insured ? 1 : 0,
                  name,
                  pin,
                });
                close();
              }}
            >
              {total === null ? 'Purchase' : `Purchase for ${credits(total)}`}
            </Button.Confirm>
          </Stack.Item>
        </Stack>
      </Section>
    </Modal>
  );
};

const BrokerView = () => {
  const { act, data } = useBackend<Data>();
  const [selectedId, setSelectedIdRaw] = useState<string | null>(null);
  const [delivery, setDelivery] = useState<Delivery>('PAD');
  const [name, setName] = useState('');
  const [focus, setFocus] = useState<Focus>({ kind: 'hull' });
  const [showSystems, setShowSystems] = useState(false);
  const [page, setPage] = useState<Page>('HANGAR');
  const [filter, setFilter] = useState('');
  const [fitsOnly, setFitsOnly] = useState(false);
  const [sort, setSort] = useState<Sort>({ key: 'price', desc: false });
  const [checkout, setCheckout] = useState(false);
  const setSelectedId = (id: string) => {
    setSelectedIdRaw(id);
    setFocus({ kind: 'hull' });
  };
  const state: BrokerState = {
    selectedId,
    setSelectedId,
    delivery,
    setDelivery,
    name,
    setName,
    focus,
    setFocus,
    showSystems,
    setShowSystems,
    page,
    setPage,
    filter,
    setFilter,
    fitsOnly,
    setFitsOnly,
    sort,
    setSort,
    checkout,
    setCheckout,
  };

  const hull =
    data.hulls.find((entry) => entry.id === selectedId) || data.hulls[0];
  if (!hull) {
    return (
      <Stack fill vertical>
        <Stack.Item>
          <Section>
            <Stack align="center">
              <Stack.Item grow>
                <BalanceBox />
              </Stack.Item>
              <Stack.Item>
                <Button icon="sign-out-alt" onClick={() => act('logout')}>
                  Log out
                </Button>
              </Stack.Item>
            </Stack>
          </Section>
        </Stack.Item>
        <Stack.Item>
          <NoticeBox info>
            The broker has no hulls on offer for your affiliation.
          </NoticeBox>
        </Stack.Item>
      </Stack>
    );
  }

  let body: ReactNode;
  switch (page) {
    case 'HANGAR':
      body = <HangarPage hull={hull} state={state} />;
      break;
    case 'CATALOG':
      body = <CatalogPage hull={hull} state={state} />;
      break;
    default: {
      const unhandled: never = page;
      throw new Error(`unhandled page ${unhandled}`);
    }
  }

  return (
    <>
      {checkout && <CheckoutModal hull={hull} state={state} />}
      {body}
    </>
  );
};

export const ShipBroker = () => {
  const { data } = useBackend<Data>();

  return (
    <Window title="Vessel Broker" width={980} height={660}>
      <Window.Content>
        {data.authenticated ? <BrokerView /> : <LoginView />}
        <ShipyardBusy operation={data.busy} />
      </Window.Content>
    </Window>
  );
};
