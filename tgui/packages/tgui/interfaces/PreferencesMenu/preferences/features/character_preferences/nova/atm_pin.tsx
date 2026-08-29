// THIS IS A NOVA SECTOR UI FILE
import { type Feature, FeatureNumberInput } from '../../base';

export const atm_pin: Feature<number> = {
  name: 'ATM PIN',
  description:
    'Four-digit PIN required to withdraw persistent credits into your round account. Remembered as a key memory when you spawn.',
  component: FeatureNumberInput,
};
