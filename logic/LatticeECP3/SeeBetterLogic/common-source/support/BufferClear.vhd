library ieee;
use ieee.std_logic_1164.all;

entity BufferClear is
	generic(
		INPUT_SIGNAL_POLARITY : std_logic := '1');
	port(
		Clock_CI        : in  std_logic;
		Reset_RI        : in  std_logic;
		Clear_SI        : in  std_logic;
		InputSignal_SI  : in  std_logic;
		OutputSignal_SO : out std_logic);
end entity BufferClear;

architecture Behavioral of BufferClear is
	signal MemoryFF_S : std_logic;
begin
	-- Change state on clock edge (synchronous).
	p_memoryzing : process(Clock_CI, Reset_RI)
	begin
		if Reset_RI = '1' then          -- asynchronous reset (active-high for FPGAs)
			MemoryFF_S <= '0';
		elsif rising_edge(Clock_CI) then
			if Clear_SI = '1' then
				MemoryFF_S <= '0';
			end if;

			if InputSignal_SI = INPUT_SIGNAL_POLARITY then
				MemoryFF_S <= '1';
			end if;
		end if;
	end process p_memoryzing;

	-- Direct flip-flop output outside.
	OutputSignal_SO <= MemoryFF_S;
end architecture Behavioral;