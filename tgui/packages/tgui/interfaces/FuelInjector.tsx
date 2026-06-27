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
};

type GasMetadata = {
  isp_mult: number;
  scrub_default: BooleanLike;
};

type Data = {
  input: SidePanel;
  chamber: SidePanel & {
    burning: BooleanLike;
    consuming: BooleanLike;
    max_pressure: number;
  };
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
          value={side.pressure}
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
          value={side.total_moles}
          minValue={0}
          maxValue={maxM}
          ranges={{
            good: [0, maxM * 0.65],
            average: [maxM * 0.65, maxM * 0.85],
            bad: [maxM * 0.85, maxM],
          }}
        >
          {`${side.total_moles.toFixed(1)} / ${maxM}`}
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
            pill.includes('BLOCKED') || pill.includes('STALLED');
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
          <LabeledList.Item label="Per-engine moles (M)">
            {p.per_engine_moles.toFixed(3)} mol/tick
          </LabeledList.Item>
          <LabeledList.Item label="Total tick moles (M×N)">
            {p.total_tick_moles.toFixed(3)} mol/tick
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

export const FuelInjector = () => {
  const { act, data } = useBackend<Data>();
  const {
    input,
    chamber,
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
              </Section>
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
