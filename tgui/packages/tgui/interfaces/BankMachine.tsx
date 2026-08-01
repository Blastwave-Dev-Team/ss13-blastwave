import {
  AnimatedNumber,
  Button,
  LabeledList,
  NoticeBox,
  Section,
} from 'tgui-core/components';
import { formatMoney } from 'tgui-core/format';
import type { BooleanLike } from 'tgui-core/react';

import { useBackend } from '../backend';
import { Window } from '../layouts';

type Data = {
  // BLASTWAVE EDIT ADDITION START - STATION_TREASURY
  account_name: string;
  // BLASTWAVE EDIT ADDITION END
  current_balance: number;
  // BLASTWAVE EDIT ADDITION START - STATION_TREASURY
  session_credits: number;
  siphon_rate: number;
  // BLASTWAVE EDIT ADDITION END
  siphoning: BooleanLike;
  station_name: string;
};

export const BankMachine = (props) => {
  const { act, data } = useBackend<Data>();
  // BLASTWAVE EDIT CHANGE START - STATION_TREASURY - ORIGINAL: const { current_balance, siphoning, station_name } = data;
  const {
    account_name,
    current_balance,
    session_credits,
    siphon_rate,
    siphoning,
    station_name,
  } = data;
  // BLASTWAVE EDIT CHANGE END

  return (
    /* BLASTWAVE EDIT CHANGE START - STATION_TREASURY - reserve identity, theft warning, and session details */
    <Window width={390} height={205}>
      <Window.Content>
        <NoticeBox danger>
          Extraction is theft from {station_name} and will be reported
        </NoticeBox>
        <Section title={account_name}>
          <LabeledList>
            <LabeledList.Item
              label="Current Balance"
              buttons={
                <Button
                  icon={siphoning ? 'times' : 'sync'}
                  content={siphoning ? 'Stop Siphoning' : 'Siphon Credits'}
                  selected={siphoning}
                  onClick={() => act(siphoning ? 'halt' : 'siphon')}
                />
              }
            >
              <AnimatedNumber
                value={current_balance}
                format={(value) => formatMoney(value)}
              />
              {' cr'}
            </LabeledList.Item>
            <LabeledList.Item label="Extraction Rate">
              {formatMoney(siphon_rate)} cr/second
            </LabeledList.Item>
            <LabeledList.Item label="Current Session">
              <AnimatedNumber
                value={session_credits}
                format={(value) => formatMoney(value)}
              />{' '}
              cr
            </LabeledList.Item>
          </LabeledList>
        </Section>
      </Window.Content>
    </Window>
    /* BLASTWAVE EDIT CHANGE END */
  );
};
