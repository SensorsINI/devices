library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package DVSAERConfigRecords is
	type tDVSAERConfig is record
		ackDelay	 : unsigned(4 downto 0);
		ackExtension : unsigned(4 downto 0);
	end record tDVSAERConfig;

	constant DVSAERCONFIG_MAX_PARAM_LENGTH : integer := 5;
	constant DVSAERCONFIG_TOTAL_LENGTH	   : integer := 5;

	constant tDVSAERConfigDefault : tDVSAERConfig := (
		ackDelay	 => to_unsigned(2, 5),
		ackExtension => to_unsigned(1, 5));
end package DVSAERConfigRecords;
