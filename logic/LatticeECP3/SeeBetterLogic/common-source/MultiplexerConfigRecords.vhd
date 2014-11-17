library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package MultiplexerConfigRecords is
	constant MULTIPLEXERCONFIG_MODULE_ADDRESS : unsigned(6 downto 0) := to_unsigned(0, 7);

	type tMultiplexerConfigParamAddresses is record
		Run_S                           : unsigned(7 downto 0);
		TimestampRun_S                  : unsigned(7 downto 0);
		TimestampReset_S                : unsigned(7 downto 0);
		ForceChipBiasEnable_S           : unsigned(7 downto 0);
		DropDVSOnTransferStall_S        : unsigned(7 downto 0);
		DropAPSOnTransferStall_S        : unsigned(7 downto 0);
		DropIMUOnTransferStall_S        : unsigned(7 downto 0);
		DropExtTriggerOnTransferStall_S : unsigned(7 downto 0);
	end record tMultiplexerConfigParamAddresses;

	constant MULTIPLEXERCONFIG_PARAM_ADDRESSES : tMultiplexerConfigParamAddresses := (
		Run_S                           => to_unsigned(0, 8),
		TimestampRun_S                  => to_unsigned(1, 8),
		TimestampReset_S                => to_unsigned(2, 8),
		ForceChipBiasEnable_S           => to_unsigned(3, 8),
		DropDVSOnTransferStall_S        => to_unsigned(4, 8),
		DropAPSOnTransferStall_S        => to_unsigned(5, 8),
		DropIMUOnTransferStall_S        => to_unsigned(6, 8),
		DropExtTriggerOnTransferStall_S => to_unsigned(7, 8));

	type tMultiplexerConfig is record
		Run_S                           : std_logic;
		TimestampRun_S                  : std_logic;
		TimestampReset_S                : std_logic;
		ForceChipBiasEnable_S           : std_logic;
		DropDVSOnTransferStall_S        : std_logic;
		DropAPSOnTransferStall_S        : std_logic;
		DropIMUOnTransferStall_S        : std_logic;
		DropExtTriggerOnTransferStall_S : std_logic;
	end record tMultiplexerConfig;

	constant tMultiplexerConfigDefault : tMultiplexerConfig := (
		Run_S                           => '0',
		TimestampRun_S                  => '0',
		TimestampReset_S                => '0',
		ForceChipBiasEnable_S           => '0',
		DropDVSOnTransferStall_S        => '1',
		DropAPSOnTransferStall_S        => '0',
		DropIMUOnTransferStall_S        => '1',
		DropExtTriggerOnTransferStall_S => '1');
end package MultiplexerConfigRecords;
