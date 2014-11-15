library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package DAVIS640 is
	constant CHIP_IDENTIFIER : unsigned(3 downto 0) := to_unsigned(6, 4);

	constant CHIP_HAS_GLOBAL_SHUTTER : std_logic := '1';
	constant CHIP_HAS_INTEGRATED_ADC : std_logic := '1';

	constant CHIP_SIZE_COLUMNS : unsigned(9 downto 0) := to_unsigned(640, 10);
	constant CHIP_SIZE_ROWS    : unsigned(8 downto 0) := to_unsigned(480, 9);

	constant DVS_AER_BUS_WIDTH : integer := 12;
	constant APS_ADC_BUS_WIDTH : integer := 10;
end package DAVIS640;