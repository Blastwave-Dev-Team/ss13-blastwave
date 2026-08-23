#define ACCOUNT_CMD "CMD"
#define ACCOUNT_CMD_NAME "Command Budget"

// Relevant budget for DS-2
#define ACCOUNT_DS2 "DS2"
#define ACCOUNT_DS2_NAME "Syndicate Budget"
#define FUNDING_SOURCE_DS2 "DS-2 funding authority"

// Relevant budget for Interdyne!
#define ACCOUNT_INT "IP"
#define ACCOUNT_INT_NAME "Interdyne Pharmaceuticals Budget"
#define FUNDING_SOURCE_INT "Interdyne Pharmaceuticals"

// Relevant budget for Tarkon!
#define ACCOUNT_TI "TI"
#define ACCOUNT_TI_NAME "Tarkon Industries Budget"
#define FUNDING_SOURCE_TI "Tarkon Industries"

#define ACCOUNT_STA "STA"
#define ACCOUNT_STA_NAME "Station Reserve"

/// Maximum recurring salary that station payroll may authorize.
#define PAYCHECK_MAXIMUM 100
/// Existing lower bound used by the accounting console for salary cuts.
#define PAYCHECK_MINIMUM_MODIFIER 0.5
/// Extra funding retained by the station reserve above department allocations.
#define STATION_RESERVE_MARGIN 0.25

#define IS_STATION_RESERVE(account) (account == SSeconomy.station_reserve_account)

#define DS2_JOB_ENFORCER 15
#define DS2_JOB_ENGINEER 16
#define DS2_JOB_SERVICE 17
#define DS2_JOB_MECHANICAL 18
#define DS2_JOB_COMMAND 19
#define DYNE_JOB_MINING 20
#define DYNE_JOB_SCIENCE 21
#define DYNE_JOB_COMMAND 22
#define TARKON_JOB_CREW 23
#define TARKON_JOB_COMMAND 24
