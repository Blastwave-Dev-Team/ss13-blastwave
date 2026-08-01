import type { BooleanLike } from 'tgui-core/react';

export type Data = {
  accounts: PlayerAccount[];
  audit_log: AuditLog[];
  crashing: BooleanLike;
  pic_file_format: string;
  // BLASTWAVE EDIT REMOVAL - STATION_TREASURY - ORIGINAL: max_pay_mod and min_pay_mod
  // BLASTWAVE EDIT ADDITION START - STATION_TREASURY
  can_manage_payroll: BooleanLike;
  max_pay: number;
  max_advances: number;
  station_reserve_balance: number;
  station_reserve_margin: number;
  // BLASTWAVE EDIT ADDITION END
  station_time: string;
  young_ian: BooleanLike;
};

type PlayerAccount = {
  id: number;
  name: string;
  balance: number;
  job: string;
  // BLASTWAVE EDIT REMOVAL - STATION_TREASURY - ORIGINAL: modifier: number;
  // BLASTWAVE EDIT ADDITION START - STATION_TREASURY
  pay: number;
  default_pay: number;
  min_pay: number;
  base_pay: number;
  uplift_pay: number;
  has_pay_override: BooleanLike;
  uplift_missed: BooleanLike;
  // BLASTWAVE EDIT ADDITION END
  num_advances: number;
};

type AuditLog = {
  account: number;
  cost: number;
  vendor: string;
  stationtime: string;
};

export enum SCREENS {
  none,
  users,
  audit,
  ian,
}

export enum SORTING {
  ascending,
  descending,
  none,
}
