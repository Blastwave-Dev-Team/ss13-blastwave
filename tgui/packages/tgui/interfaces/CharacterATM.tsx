// THIS IS A NOVA SECTOR UI FILE
import { useState } from 'react';
import {
  Button,
  Input,
  LabeledList,
  NoticeBox,
  RestrictedInput,
  Section,
  Stack,
} from 'tgui-core/components';
import { formatMoney } from 'tgui-core/format';
import type { BooleanLike } from 'tgui-core/react';

import { useBackend } from '../backend';
import { Window } from '../layouts';

type Data = {
  operational: BooleanLike;
  offline: BooleanLike;
  has_uuid: BooleanLike;
  has_id: BooleanLike;
  ledger_balance: number;
  account_balance: number;
  remaining_deposit: number;
  remaining_withdraw: number;
};

export const CharacterATM = () => {
  const { act, data } = useBackend<Data>();
  const {
    operational,
    offline,
    has_uuid,
    has_id,
    ledger_balance,
    account_balance,
    remaining_deposit,
    remaining_withdraw,
  } = data;
  const [amount, setAmount] = useState(1);
  const [amountIsValid, setAmountIsValid] = useState(true);
  const [pin, setPin] = useState('');

  return (
    <Window title="Automated Teller" width={380} height={360}>
      <Window.Content>
        <Stack fill vertical>
          {!operational && (
            <Stack.Item>
              <NoticeBox danger>This terminal is out of order.</NoticeBox>
            </Stack.Item>
          )}
          {!!operational && !!offline && (
            <Stack.Item>
              <NoticeBox danger>Persistent ledger is offline.</NoticeBox>
            </Stack.Item>
          )}
          {!!operational && !offline && !has_uuid && (
            <Stack.Item>
              <NoticeBox>No character identity on file.</NoticeBox>
            </Stack.Item>
          )}
          {!!operational && !offline && !!has_uuid && !has_id && (
            <Stack.Item>
              <NoticeBox>Present a matching personal ID.</NoticeBox>
            </Stack.Item>
          )}
          <Stack.Item>
            <Section title="Balances">
              <LabeledList>
                <LabeledList.Item label="Persistent ledger">
                  {formatMoney(ledger_balance)} cr
                </LabeledList.Item>
                <LabeledList.Item label="Round account">
                  {formatMoney(account_balance)} cr
                </LabeledList.Item>
                <LabeledList.Item label="Deposit remaining">
                  {formatMoney(remaining_deposit)} cr
                </LabeledList.Item>
                <LabeledList.Item label="Withdraw remaining">
                  {formatMoney(remaining_withdraw)} cr
                </LabeledList.Item>
              </LabeledList>
            </Section>
          </Stack.Item>
          <Stack.Item>
            <Section title="Transaction">
              <LabeledList>
                <LabeledList.Item label="Amount">
                  <RestrictedInput
                    width="8em"
                    minValue={1}
                    maxValue={Math.max(
                      remaining_deposit,
                      remaining_withdraw,
                      1,
                    )}
                    value={amount}
                    onChange={setAmount}
                    onValidationChange={setAmountIsValid}
                  />
                </LabeledList.Item>
                <LabeledList.Item label="PIN">
                  <Input
                    expensive
                    width="8em"
                    maxLength={4}
                    placeholder="Withdraw only"
                    value={pin}
                    onChange={setPin}
                  />
                </LabeledList.Item>
              </LabeledList>
              <Stack mt={1}>
                <Stack.Item grow>
                  <Button
                    fluid
                    icon="arrow-up"
                    disabled={
                      !operational ||
                      !!offline ||
                      !has_uuid ||
                      !has_id ||
                      !amountIsValid
                    }
                    onClick={() => act('deposit', { amount })}
                  >
                    Deposit
                  </Button>
                </Stack.Item>
                <Stack.Item grow>
                  <Button
                    fluid
                    icon="arrow-down"
                    disabled={
                      !operational ||
                      !!offline ||
                      !has_uuid ||
                      !has_id ||
                      !amountIsValid ||
                      pin.length < 1
                    }
                    onClick={() => act('withdraw', { amount, pin })}
                  >
                    Withdraw
                  </Button>
                </Stack.Item>
              </Stack>
            </Section>
          </Stack.Item>
        </Stack>
      </Window.Content>
    </Window>
  );
};
