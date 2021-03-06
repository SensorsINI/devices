library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-------------------------------------------------------------------------------

entity PulseGenerator_tb is
end entity PulseGenerator_tb;

-------------------------------------------------------------------------------

architecture Testbench of PulseGenerator_tb is
	-- component generics
	constant PULSE_EVERY_CYCLES : integer   := 20;
	constant PULSE_FOR_CYCLES   : integer   := 1;
	constant PULSE_POLARITY     : std_logic := '1';

	-- component ports
	signal Clock_C    : std_logic;
	signal Reset_R    : std_logic;
	signal Clear_S    : std_logic;
	signal PulseOut_S : std_logic;

	-- clock
	signal Clk_C : std_logic := '1';
begin                                   -- architecture Test

	-- component instantiation
	DUT : entity work.PulseGenerator
		generic map(
			SIZE => 5)
		port map(
			Clock_CI         => Clock_C,
			Reset_RI         => Reset_R,
			PulsePolarity_SI => PULSE_POLARITY,
			PulseInterval_DI => to_unsigned(PULSE_EVERY_CYCLES, 5),
			PulseLength_DI   => to_unsigned(PULSE_FOR_CYCLES, 5),
			Zero_SI          => Clear_S,
			PulseOut_SO      => PulseOut_S);

	-- clock generation
	Clk_C   <= not Clk_C after 0.5 ns;
	Clock_C <= Clk_C;

	-- waveform generation
	WaveGen_Proc : process
	begin
		Reset_R <= '0';
		Clear_S <= '0';

		-- pulse reset
		wait for 2 ns;
		Reset_R <= '1';
		wait for 3 ns;
		Reset_R <= '0';

		wait for 150 ns;
		Clear_S <= '1';
		wait for 1 ns;
		Clear_S <= '0';

		wait;
	end process WaveGen_Proc;
end architecture Testbench;
