import type { FeatureChoiced } from '../base';
import { FeatureDropdownInput } from '../dropdowns';

export const objective_equipment_delivery: FeatureChoiced = {
  name: 'Uplink Objective Equipment',
  description:
    'How objective-specific equipment (such as the nuclear core or supermatter extraction kits) is delivered to you. \
Backpack attempts to place it on you directly, falling back to a free uplink supply pod if it does not fit. \
Uplink Supply Pod always delivers it via a free supply pod that you call down from your uplink.',
  component: FeatureDropdownInput,
};
