// THIS IS A NOVA SECTOR UI FILE
import { useState } from 'react';
import {
  Box,
  Button,
  Collapsible,
  Icon,
  LabeledControls,
  LabeledList,
  NoticeBox,
  ProgressBar,
  Section,
  Slider,
  Stack,
  Tooltip,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

import { useBackend } from '../backend';
import { getGasColor, getGasLabel } from '../constants';
import { Window } from '../layouts';

type FilterEntry = {
  gasId: string;
  gasName: string;
  enabled: BooleanLike;
};

type SidePanel = {
  connected: BooleanLike;
  pressure: number;
  temperature: number;
  total_moles: number;
  max_moles: number;
  max_pressure?: number;
  gas_composition: Record<string, number>;
};

type Performance = {
  estimated_isp: number;
  thrust_efficiency: number;
  delta_v: number;
  base_isp: number;
  gas_multiplier: number;
  chemical_bonus: number;
  power_fraction: number;
  linked_engines: number;
  piped_engines: number;
  adjacent_engines: number;
  link_mode: string;
  active_share_count: number;
  per_engine_moles: number;
  total_tick_moles: number;
  feed_connected: BooleanLike;
  ship_mass: number;
  ship_mass_unknown: BooleanLike;
  target_mol_s?: number;
  delivered_mol_s?: number;
  spool_pct?: number;
  feed_pressure?: number;
};

type GasMetadata = {
  isp_mult: number;
  scrub_default: BooleanLike;
};

type Preheat = {
  enabled: BooleanLike;
  setpoint: number;
  setpoint_min: number;
  setpoint_max: number;
  power_draw: number;
  ignition_temp: number;
};

type Data = {
  input: SidePanel;
  chamber: SidePanel & {
    burning: BooleanLike;
    consuming: BooleanLike;
    ignited?: BooleanLike;
    max_pressure: number;
    feed_moles?: number;
    stored_moles?: number;
  };
  preheat: Preheat;
  exhaust: SidePanel;
  filters: {
    intake: FilterEntry[];
    scrub: FilterEntry[];
    intake_rejection_ratio: number;
    scrub_eligible_ratio: number;
  };
  performance: Performance;
  status_pills: string[];
  tank: { installed: BooleanLike; name: string; moles: number } | null;
  can_flameout: BooleanLike;
  parts: {
    matter_bin_rating: number;
    micro_laser_rating: number;
    chamber_volume: number;
  };
  gas_metadata?: Record<string, GasMetadata>;
};

const PLASMA_IGNITION_K = 373.15;
const TEMP_MAX = 1200;

const ConnectionButton = (props: { connected: BooleanLike }) => {
  const { connected } = props;
  return (
    <Button
      icon={connected ? 'check' : 'times'}
      color={connected ? 'green' : 'red'}
      content={connected ? 'Connected' : 'Disconnected'}
      disabled
    />
  );
};

type SideMetricsProps = {
  side: SidePanel;
  maxPressure?: number;
};

const SideMetrics = (props: SideMetricsProps) => {
  const { side, maxPressure } = props;
  const maxP = maxPressure || side.max_pressure || 450;
  const maxM = side.max_moles || 250;

  if (!side.connected && side.total_moles <= 0) {
    return null;
  }

  return (
    <LabeledList>
      <LabeledList.Item label="Pressure">
        <ProgressBar
          value={Math.min(side.pressure, maxP)}
          minValue={0}
          maxValue={maxP}
          ranges={{
            good: [0, maxP * 0.65],
            average: [maxP * 0.65, maxP * 0.85],
            bad: [maxP * 0.85, maxP],
          }}
        >
          {`${side.pressure.toFixed(1)} kPa`}
        </ProgressBar>
      </LabeledList.Item>
      <LabeledList.Item label="Temperature">
        <ProgressBar
          value={side.temperature}
          minValue={0}
          maxValue={TEMP_MAX}
          ranges={{
            good: [0, 320],
            average: [320, PLASMA_IGNITION_K],
            bad: [PLASMA_IGNITION_K, TEMP_MAX],
          }}
        >
          {`${side.temperature.toFixed(1)} K`}
        </ProgressBar>
      </LabeledList.Item>
      <LabeledList.Item label="Moles">
        <ProgressBar
          value={Math.min(side.total_moles, maxM)}
          minValue={0}
          maxValue={maxM}
          ranges={{
            good: [0, maxM * 0.65],
            average: [maxM * 0.65, maxM * 0.85],
            bad: [maxM * 0.85, maxM],
          }}
        >
          {`${side.total_moles.toFixed(1)} / ${Number(maxM).toFixed(1)}`}
          {side.total_moles > maxM ? ' (OVER)' : ''}
        </ProgressBar>
      </LabeledList.Item>
    </LabeledList>
  );
};

type FilterSectionProps = {
  stage: 'intake' | 'scrub';
  filters: FilterEntry[];
  note?: string;
  onToggle: (gasId: string) => void;
  onPreset: (preset: string) => void;
};

const FilterSection = (props: FilterSectionProps) => {
  const { stage, filters, note, onToggle, onPreset } = props;
  const isIntake = stage === 'intake';
  const title = isIntake ? 'Intake Filters' : 'Scrub Filters';
  const hint = isIntake
    ? 'Checked gases are pulled from L1 into the chamber.'
    : 'Checked gases are scrubbed from chamber to L3.';

  return (
    <Section title={title}>
      <Box color="label" mb={1}>
        {hint}
      </Box>
      {note &&
        (note.includes('All line') ? (
          <NoticeBox mb={1} success>
            {note}
          </NoticeBox>
        ) : (
          <NoticeBox mb={1}>{note}</NoticeBox>
        ))}
      <LabeledList>
        <LabeledList.Item label="Filters">
          {filters.map((filter) => (
            <Button
              key={filter.gasId}
              icon={filter.enabled ? 'check-square-o' : 'square-o'}
              selected={!!filter.enabled}
              content={getGasLabel(filter.gasId, filter.gasName)}
              onClick={() => onToggle(filter.gasId)}
            />
          ))}
        </LabeledList.Item>
        <LabeledList.Item label="Presets">
          {isIntake ? (
            <>
              <Button
                content="Propellants"
                onClick={() => onPreset('intake_propellants')}
              />
              <Button
                content="Allow all"
                onClick={() => onPreset('intake_all')}
              />
            </>
          ) : (
            <>
              <Button
                content="Auto slag"
                onClick={() => onPreset('scrub_auto')}
              />
              <Button
                content="Burn products"
                onClick={() => onPreset('scrub_burn_products')}
              />
            </>
          )}
        </LabeledList.Item>
      </LabeledList>
    </Section>
  );
};

type GasListProps = {
  composition: Record<string, number>;
  totalMoles: number;
  showAll: boolean;
  onToggleShowAll: () => void;
  intakeEnabled?: Record<string, boolean>;
  gasMetadata: Record<string, GasMetadata>;
};

const GasList = (props: GasListProps) => {
  const {
    composition,
    totalMoles,
    showAll,
    onToggleShowAll,
    intakeEnabled,
    gasMetadata,
  } = props;

  const entries = Object.entries(composition)
    .filter(([, frac]) => showAll || frac > 0.001)
    .sort((a, b) => b[1] - a[1]);

  return (
    <Section
      title="Gas Composition"
      buttons={
        <Button
          content={showAll ? 'Hide empty' : 'Show all'}
          onClick={onToggleShowAll}
        />
      }
    >
      {!entries.length || totalMoles <= 0 ? (
        <NoticeBox>No gas detected</NoticeBox>
      ) : (
        <LabeledList>
          {entries.map(([gasId, frac]) => {
            const blocked = intakeEnabled && !intakeEnabled[gasId];
            const moles = frac * totalMoles;
            const pct = (frac * 100).toFixed(1);
            const meta = gasMetadata[gasId];
            return (
              <LabeledList.Item
                key={gasId}
                label={
                  <>
                    {getGasLabel(gasId)}
                    {blocked && (
                      <Box as="span" color="bad" ml={0.5}>
                        (blocked)
                      </Box>
                    )}
                  </>
                }
              >
                <ProgressBar
                  value={frac}
                  minValue={0}
                  maxValue={1}
                  color={getGasColor(gasId)}
                  style={{ opacity: blocked ? 0.35 : 1 }}
                >
                  {`${moles.toFixed(1)} mol (${pct}%)`}
                </ProgressBar>
                {meta && (
                  <Box color="label" mt={0.25}>
                    ISP mult: {meta.isp_mult.toFixed(2)}×
                    {blocked && ' — Not permitted through intake filter.'}
                  </Box>
                )}
              </LabeledList.Item>
            );
          })}
        </LabeledList>
      )}
    </Section>
  );
};

type PerformanceSectionProps = {
  performance: Performance;
  statusPills: string[];
};

const PerformanceSection = (props: PerformanceSectionProps) => {
  const { performance: p, statusPills } = props;
  const dvText = p.ship_mass_unknown
    ? '—'
    : p.delta_v > 0
      ? p.delta_v.toFixed(2)
      : '0.00';

  return (
    <Section title="Performance">
      {statusPills.length ? (
        statusPills.map((pill) => {
          const isDanger =
            pill.includes('BLOCKED') ||
            pill.includes('STALLED') ||
            pill.includes('Relief');
          const isSuccess = pill.includes('Reaction Active');
          if (isDanger) {
            return (
              <NoticeBox key={pill} mb={1} danger>
                {pill}
              </NoticeBox>
            );
          }
          if (isSuccess) {
            return (
              <NoticeBox key={pill} mb={1} success>
                {pill}
              </NoticeBox>
            );
          }
          return (
            <NoticeBox key={pill} mb={1} info>
              {pill}
            </NoticeBox>
          );
        })
      ) : (
        <NoticeBox mb={1}>Idle</NoticeBox>
      )}
      <LabeledControls mb={1}>
        <LabeledControls.Item label="Est. ISP">
          <Box bold>{p.estimated_isp.toFixed(2)}</Box>
        </LabeledControls.Item>
        <LabeledControls.Item label="Thrust Eff.">
          <ProgressBar
            value={p.thrust_efficiency}
            minValue={0}
            maxValue={1}
            ranges={{
              good: [0.65, 1],
              average: [0.35, 0.65],
              bad: [0, 0.35],
            }}
          >
            {(p.thrust_efficiency * 100).toFixed(0)}%
          </ProgressBar>
        </LabeledControls.Item>
        <LabeledControls.Item label="Est. Δv">
          <Box bold color={p.ship_mass_unknown ? 'label' : 'good'}>
            {dvText}
            {!p.ship_mass_unknown && ' m/s'}
          </Box>
        </LabeledControls.Item>
      </LabeledControls>
      <Collapsible title="Factor breakdown" open={false}>
        <LabeledList>
          <LabeledList.Item label="Base ISP">
            {p.base_isp.toFixed(2)}
          </LabeledList.Item>
          <LabeledList.Item label="Gas multiplier">
            {p.gas_multiplier.toFixed(2)}×
          </LabeledList.Item>
          <LabeledList.Item label="Chemical bonus">
            {p.chemical_bonus.toFixed(2)}×
          </LabeledList.Item>
          <LabeledList.Item label="Power fraction">
            {(p.power_fraction * 100).toFixed(0)}%
          </LabeledList.Item>
          <LabeledList.Item label="Linked engines">
            {p.linked_engines}
            {p.link_mode !== 'none' && ` (${p.link_mode})`}
          </LabeledList.Item>
          <LabeledList.Item label="Manifold link">
            {p.piped_engines} piped / {p.adjacent_engines} adjacent
            {p.feed_connected ? ' — feed port connected' : ' — feed port open'}
          </LabeledList.Item>
          <LabeledList.Item label="Active shares (N)">
            {p.active_share_count}
          </LabeledList.Item>
          <LabeledList.Item label="Per-engine demand (rated)">
            {p.per_engine_moles.toFixed(3)} mol/s
          </LabeledList.Item>
          <LabeledList.Item label="Total demand (rated)">
            {p.total_tick_moles.toFixed(3)} mol/s
          </LabeledList.Item>
          <LabeledList.Item label="Target mass flow">
            {(p.target_mol_s ?? 0).toFixed(3)} mol/s
            {(p.target_mol_s ?? 0) <= 0 ? ' (no throttle)' : ''}
          </LabeledList.Item>
          <LabeledList.Item label="Delivered mass flow">
            {(p.delivered_mol_s ?? 0).toFixed(3)} mol/s
          </LabeledList.Item>
          <LabeledList.Item label="Spool">
            {((p.spool_pct ?? 0) * 100).toFixed(0)}%
            {p.feed_pressure !== undefined &&
              ` @ ${p.feed_pressure.toFixed(0)} kPa rail`}
          </LabeledList.Item>
          {!p.ship_mass_unknown && (
            <LabeledList.Item label="Ship mass">
              {p.ship_mass} turfs
            </LabeledList.Item>
          )}
        </LabeledList>
      </Collapsible>
    </Section>
  );
};

const FlowArrow = () => (
  <Stack.Item align="center">
    <Icon name="arrow-right" size={1.5} color="label" />
  </Stack.Item>
);

type ChamberConditioningProps = {
  chamber: Data['chamber'];
  preheat: Preheat;
  onIgnite: () => void;
  onTogglePreheat: () => void;
  onSetTarget: (target: number) => void;
};

const ChamberConditioning = (props: ChamberConditioningProps) => {
  const { chamber, preheat, onIgnite, onTogglePreheat, onSetTarget } = props;
  const atIgnitionTemp = chamber.temperature >= preheat.ignition_temp;

  return (
    <Section
      title="Chamber Conditioning"
      buttons={
        <Button
          icon="bolt"
          color="orange"
          content="Ignite"
          disabled={!!chamber.consuming || chamber.total_moles <= 0}
          tooltip={
            chamber.total_moles <= 0
              ? 'Chamber is empty'
              : 'Spark the chamber. Combustible mixes self-heat; inert mixes fizzle.'
          }
          onClick={onIgnite}
        />
      }
    >
      <LabeledList>
        <LabeledList.Item label="Preheater">
          <Button
            icon={preheat.enabled ? 'power-off' : 'times'}
            selected={!!preheat.enabled}
            content={preheat.enabled ? 'On' : 'Off'}
            onClick={onTogglePreheat}
          />
          <Box as="span" color="label" ml={1}>
            {(preheat.power_draw / 1000).toFixed(0)} kW while heating
          </Box>
        </LabeledList.Item>
        <LabeledList.Item label="Setpoint">
          <Slider
            value={preheat.setpoint}
            minValue={preheat.setpoint_min}
            maxValue={preheat.setpoint_max}
            step={5}
            unit="K"
            onChange={(_e, value) => onSetTarget(value)}
          />
        </LabeledList.Item>
        <LabeledList.Item label="Ignition threshold">
          <Box as="span" color={atIgnitionTemp ? 'good' : 'label'}>
            {preheat.ignition_temp.toFixed(0)} K
            {atIgnitionTemp ? ' — chamber at temperature' : ''}
          </Box>
        </LabeledList.Item>
      </LabeledList>
    </Section>
  );
};

export const FuelInjector = () => {
  const { act, data } = useBackend<Data>();
  const {
    input,
    chamber,
    preheat,
    exhaust,
    filters,
    performance,
    status_pills = [],
    tank,
    can_flameout,
    parts,
    gas_metadata = {},
  } = data;

  const [showAllGases, setShowAllGases] = useState({
    input: false,
    chamber: false,
    exhaust: false,
  });

  const intakeEnabled = Object.fromEntries(
    filters.intake.map((f) => [f.gasId, !!f.enabled]),
  );

  const chamberStatus = chamber.burning
    ? 'Burning'
    : chamber.consuming
      ? 'Consuming'
      : 'Idle';

  const intakeNote = (() => {
    if (!input.connected || input.total_moles <= 0) return undefined;
    const reject = filters.intake_rejection_ratio;
    if (reject > 0.001) {
      return `${(reject * 100).toFixed(0)}% of line moles rejected at intake`;
    }
    return 'All line gases accepted';
  })();

  const scrubNote =
    chamber.total_moles > 0
      ? `${(filters.scrub_eligible_ratio * 100).toFixed(0)}% of chamber mix eligible for L3 scrub`
      : undefined;

  const renderSidePanel = (
    panelKey: 'input' | 'exhaust',
    side: SidePanel,
    options: {
      showIntakeFilters?: boolean;
      showScrubFilters?: boolean;
      filterNote?: string;
    } = {},
  ) => (
    <Stack.Item grow basis={0}>
      <Section
        title={panelKey === 'input' ? 'Layer 1 Intake' : 'Layer 3 Exhaust'}
        scrollable
        fill
        height="100%"
        buttons={<ConnectionButton connected={side.connected} />}
      >
        {options.showIntakeFilters && (
          <FilterSection
            stage="intake"
            filters={filters.intake}
            note={options.filterNote}
            onToggle={(gasId) => act('toggle_intake_filter', { gas_id: gasId })}
            onPreset={(preset) => act('filter_preset', { preset })}
          />
        )}
        {options.showScrubFilters && (
          <FilterSection
            stage="scrub"
            filters={filters.scrub}
            note={options.filterNote}
            onToggle={(gasId) => act('toggle_scrub_filter', { gas_id: gasId })}
            onPreset={(preset) => act('filter_preset', { preset })}
          />
        )}
        <Section
          title={panelKey === 'input' ? 'Line Reading' : 'Exhaust Line'}
        >
          {!side.connected && (
            <NoticeBox mb={1}>
              {panelKey === 'input'
                ? 'Pipe not connected'
                : 'Exhaust line not connected'}
            </NoticeBox>
          )}
          <SideMetrics side={side} />
        </Section>
        <GasList
          composition={side.gas_composition || {}}
          totalMoles={side.total_moles}
          showAll={showAllGases[panelKey]}
          onToggleShowAll={() =>
            setShowAllGases((s) => ({ ...s, [panelKey]: !s[panelKey] }))
          }
          intakeEnabled={panelKey === 'input' ? intakeEnabled : undefined}
          gasMetadata={gas_metadata}
        />
      </Section>
    </Stack.Item>
  );

  return (
    <Window width={960} height={580} title="Fuel Injector">
      <Window.Content scrollable>
        <Section title="Summary">
          <LabeledList>
            <LabeledList.Item label="Chamber">{chamberStatus}</LabeledList.Item>
            <LabeledList.Item label="Parts">
              Matter bin T{parts.matter_bin_rating}, micro laser T
              {parts.micro_laser_rating}, {parts.chamber_volume} L chamber
            </LabeledList.Item>
            <LabeledList.Item label="Handheld tank">
              {tank
                ? `${tank.name} (${tank.moles.toFixed(1)} mol)`
                : 'None installed'}
            </LabeledList.Item>
          </LabeledList>
          {!!chamber.burning && (
            <NoticeBox mt={1}>Chamber reaction is active.</NoticeBox>
          )}
          {!!chamber.consuming && !chamber.burning && (
            <NoticeBox mt={1}>Chamber is consuming propellant.</NoticeBox>
          )}
        </Section>

        <Stack fill height="420px">
          {renderSidePanel('input', input, {
            showIntakeFilters: true,
            filterNote: intakeNote,
          })}
          <FlowArrow />
          <Stack.Item grow basis={0}>
            <Section title="Reaction Chamber" scrollable fill height="100%">
              <PerformanceSection
                performance={performance}
                statusPills={status_pills}
              />
              <Section title="Chamber Mix">
                <SideMetrics
                  side={chamber}
                  maxPressure={chamber.max_pressure}
                />
                {(chamber.feed_moles !== undefined ||
                  chamber.stored_moles !== undefined) && (
                  <LabeledList>
                    <LabeledList.Item label="L2 feed">
                      {(chamber.feed_moles ?? 0).toFixed(1)} mol
                    </LabeledList.Item>
                    <LabeledList.Item label="Stored total">
                      {(chamber.stored_moles ?? 0).toFixed(1)} mol
                    </LabeledList.Item>
                  </LabeledList>
                )}
              </Section>
              {preheat && (
                <ChamberConditioning
                  chamber={chamber}
                  preheat={preheat}
                  onIgnite={() => act('ignite')}
                  onTogglePreheat={() => act('toggle_preheat')}
                  onSetTarget={(target) =>
                    act('set_preheat_target', { target })
                  }
                />
              )}
              <GasList
                composition={chamber.gas_composition || {}}
                totalMoles={chamber.total_moles}
                showAll={showAllGases.chamber}
                onToggleShowAll={() =>
                  setShowAllGases((s) => ({ ...s, chamber: !s.chamber }))
                }
                gasMetadata={gas_metadata}
              />
            </Section>
          </Stack.Item>
          <FlowArrow />
          {renderSidePanel('exhaust', exhaust, {
            showScrubFilters: true,
            filterNote: scrubNote,
          })}
        </Stack>

        <Section
          title="Emergency"
          buttons={
            can_flameout ? (
              <Button
                color="orange"
                content="Flameout"
                onClick={() => act('flameout')}
              />
            ) : (
              <Tooltip content="Linked engines must be off" position="top">
                <Button color="orange" content="Flameout" disabled />
              </Tooltip>
            )
          }
        >
          <Box color="label">
            Dump the reaction chamber through linked engine nozzles. Engines
            must be off.
          </Box>
        </Section>
      </Window.Content>
    </Window>
  );
};
