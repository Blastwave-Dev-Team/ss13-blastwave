import {
  Blink,
  Button,
  Modal,
  NumberInput,
  NoticeBox, // BLASTWAVE EDIT ADDITION - STATION_TREASURY
  Section,
  Stack,
  Table,
} from 'tgui-core/components';
import { useBackend, useSharedState } from '../../backend';
import { getRandomDoomMessage } from './helpers';
import { SortButton } from './Sort';
import { type Data, SORTING } from './types';

export const UsersScreen = () => {
  const { act, data } = useBackend<Data>();
  // BLASTWAVE EDIT CHANGE START - STATION_TREASURY - ORIGINAL: crashing, accounts, max_pay_mod, min_pay_mod, max_advances
  const {
    crashing,
    accounts,
    can_manage_payroll,
    max_pay,
    max_advances,
    station_reserve_balance,
    station_reserve_margin,
  } = data;
  // BLASTWAVE EDIT CHANGE END

  const [accountNameSorting, setAccountNameSorting] = useSharedState(
    'sorting_account_name',
    SORTING.ascending,
  );
  const [balanceSorting, setBalanceSorting] = useSharedState(
    'sorting_balance',
    SORTING.none,
  );
  const [jobSorting, setJobSorting] = useSharedState(
    'sorting_job',
    SORTING.none,
  );

  const accountsSorted = accounts.sort((a, b) => {
    if (accountNameSorting === SORTING.ascending) {
      return a.name > b.name ? 1 : -1;
    } else if (accountNameSorting === SORTING.descending) {
      return a.name > b.name ? -1 : 1;
    } else if (balanceSorting === SORTING.ascending) {
      return a.balance - b.balance;
    } else if (balanceSorting === SORTING.descending) {
      return b.balance - a.balance;
    } else if (jobSorting === SORTING.ascending) {
      return a.job > b.job ? 1 : -1;
    } else if (jobSorting === SORTING.descending) {
      return a.job > b.job ? -1 : 1;
    }
    return 0;
  });

  return (
    /* BLASTWAVE EDIT CHANGE START - STATION_TREASURY - treasury summary and effective salary controls */
    <Stack vertical fill>
      <Stack.Item>
        <NoticeBox>
          Station Reserve: {station_reserve_balance} cr · NT retained margin:{' '}
          {station_reserve_margin}%
          {!can_manage_payroll && ' · Read-only access'}
        </NoticeBox>
      </Stack.Item>
      <Stack.Item grow>
        <Section scrollable fill>
          {!!crashing && (
            <Modal width="300px" align="center">
              <Blink time={500} interval={500}>
                {getRandomDoomMessage()}
              </Blink>
            </Modal>
          )}
          <Table>
            <Table.Row>
          <Table.Cell bold>
            <Stack>
              <Stack.Item grow fontSize="14px">
                Account
              </Stack.Item>
              <Stack.Item>
                <SortButton
                  sorting={accountNameSorting}
                  setSorting={setAccountNameSorting}
                  otherSorters={[setBalanceSorting, setJobSorting]}
                />
              </Stack.Item>
            </Stack>
          </Table.Cell>
          <Table.Cell bold>
            <Stack>
              <Stack.Item grow fontSize="14px">
                Balance
              </Stack.Item>
              <Stack.Item>
                <SortButton
                  sorting={balanceSorting}
                  setSorting={setBalanceSorting}
                  otherSorters={[setAccountNameSorting, setJobSorting]}
                />
              </Stack.Item>
            </Stack>
          </Table.Cell>
          <Table.Cell bold>
            <Stack>
              <Stack.Item grow fontSize="14px">
                Assignment
              </Stack.Item>
              <Stack.Item>
                <SortButton
                  sorting={jobSorting}
                  setSorting={setJobSorting}
                  otherSorters={[setAccountNameSorting, setBalanceSorting]}
                />
              </Stack.Item>
            </Stack>
          </Table.Cell>
          <Table.Cell bold fontSize="14px">
            Pay
          </Table.Cell>
          <Table.Cell bold fontSize="14px">
            Advances
          </Table.Cell>
            </Table.Row>
            {accountsSorted.map((account, index) => (
              <Table.Row
                key={`account_${account.id}_${index}`}
                className="Accounting__TableHeader"
              >
                <Table.Cell>{account.name}</Table.Cell>
                <Table.Cell className="Accounting__TableCellSides">
                  {account.balance} cr
                </Table.Cell>
                <Table.Cell className="Accounting__TableCellSides">
                  {account.job}
                </Table.Cell>
                <Table.Cell className="Accounting__TableCellSides">
                  <Stack vertical>
                    <Stack.Item>
                      <Stack>
                        <Stack.Item grow>
                          <NumberInput
                            fluid
                            value={account.pay}
                            minValue={account.min_pay}
                            maxValue={max_pay}
                            step={1}
                            format={(value) => `${value.toFixed(0)} cr`}
                            disabled={!can_manage_payroll}
                            onChange={(value) =>
                              act('change_pay', {
                                account_id: account.id,
                                pay: value,
                              })
                            }
                          />
                        </Stack.Item>
                        <Stack.Item>
                          <Button
                            icon="rotate-left"
                            tooltip={`Reset to ${account.default_pay} cr`}
                            disabled={
                              !can_manage_payroll || !account.has_pay_override
                            }
                            onClick={() =>
                              act('reset_pay', { account_id: account.id })
                            }
                          />
                        </Stack.Item>
                      </Stack>
                    </Stack.Item>
                    <Stack.Item
                      color={account.uplift_missed ? 'bad' : undefined}
                      fontSize="10px"
                    >
                      {account.base_pay} dept
                      {account.uplift_pay > 0 &&
                        ` + ${account.uplift_pay} reserve`}
                      {!!account.uplift_missed && ' (uplift missed)'}
                    </Stack.Item>
                  </Stack>
                </Table.Cell>
                <Table.Cell className="Accounting__TableCellSides">
                  <Stack>
                    <Stack.Item>
                      <Button
                        ml={0.5}
                        mr={0.5}
                        height="12px"
                        width="12px"
                        fontSize="8px"
                        disabled={
                          !can_manage_payroll ||
                          account.num_advances >= max_advances
                        }
                        onClick={() =>
                          act('paycheck_advance', {
                            account_id: account.id,
                          })
                        }
                      >
                        +
                      </Button>
                    </Stack.Item>
                    <Stack.Item>{account.num_advances}</Stack.Item>
                  </Stack>
                </Table.Cell>
              </Table.Row>
            ))}
          </Table>
        </Section>
      </Stack.Item>
    </Stack>
    /* BLASTWAVE EDIT CHANGE END */
  );
};
