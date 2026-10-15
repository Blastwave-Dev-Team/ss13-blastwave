// THIS IS A NOVA SECTOR UI FILE
import { Input, LabeledList } from 'tgui-core/components';

type Props = {
  value: string;
  onChange: (value: string) => void;
};

/** Ledger PIN field, the same four-digit confirm the ATM asks for on withdraw. */
export const ShipyardPin = (props: Props) => {
  const { value, onChange } = props;
  return (
    <LabeledList.Item label="PIN">
      <Input
        expensive
        width="8em"
        maxLength={4}
        placeholder="Ledger PIN"
        value={value}
        onChange={onChange}
      />
    </LabeledList.Item>
  );
};
