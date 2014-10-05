library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.ceil;
use ieee.math_real.log2;
use work.Settings.USB_CLOCK_FREQ;
use work.Settings.USB_BURST_WRITE_LENGTH;
use work.FIFORecords.all;
use work.FX3ConfigRecords.all;

entity FX3Statemachine is
	port(
		Clock_CI                    : in  std_logic;
		Reset_RI                    : in  std_logic;

		-- USB FIFO flags
		USBFifoThread0Full_SI       : in  std_logic;
		USBFifoThread0AlmostFull_SI : in  std_logic;
		USBFifoThread1Full_SI       : in  std_logic;
		USBFifoThread1AlmostFull_SI : in  std_logic;

		-- USB FIFO control lines
		USBFifoWrite_SBO            : out std_logic;
		USBFifoPktEnd_SBO           : out std_logic;
		USBFifoAddress_DO           : out std_logic_vector(1 downto 0);

		-- Input FIFO (from Multiplexer)
		InFifoControl_SI            : in  tFromFifoReadSide;
		InFifoControl_SO            : out tToFifoReadSide;

		-- Configuration input
		FX3Config_DI                : in  tFX3Config);
end FX3Statemachine;

architecture Behavioral of FX3Statemachine is
	attribute syn_enum_encoding : string;

	type tState is (stIdle0, stPrepareEarlyPacket0, stEarlyPacket0, stPrepareWrite0, stWriteFirst0, stWriteMiddle0, stWriteLast0, stPrepareSwitch0, stSwitch0,
		            stIdle1, stPrepareEarlyPacket1, stEarlyPacket1, stPrepareWrite1, stWriteFirst1, stWriteMiddle1, stWriteLast1, stPrepareSwitch1, stSwitch1);
	attribute syn_enum_encoding of tState : type is "onehot";

	-- present and next state
	signal State_DP, State_DN : tState;

	-- USB thread constants (for switching when current buffer full)
	constant USB_THREAD0 : std_logic_vector := "00";
	constant USB_THREAD1 : std_logic_vector := "01";
	--constant USB_THREAD2 : std_logic_vector := "10";
	--constant USB_THREAD3 : std_logic_vector := "11";

	-- calculated constants
	constant USB_EARLY_PACKET_CYCLES       : integer := USB_CLOCK_FREQ * 1_000;
	constant USB_EARLY_PACKET_CYCLES_WIDTH : integer := integer(ceil(log2(real(USB_EARLY_PACKET_CYCLES + 1))));
	constant USB_EARLY_PACKET_WIDTH        : integer := USB_EARLY_PACKET_CYCLES_WIDTH + tFX3Config.EarlyPacketDelay_D'length;

	-- number of intermediate writes to perform (including zero, so a value of 5 means 6 write cycles)
	constant USB_BURST_WRITE_CYCLES : integer := USB_BURST_WRITE_LENGTH - 3;
	constant USB_BURST_WRITE_WIDTH  : integer := integer(ceil(log2(real(USB_BURST_WRITE_CYCLES + 1))));

	-- write burst counter
	signal CyclesCount_S, CyclesNotify_S : std_logic;

	-- early packet counter, to keep a certain flow of USB traffic going even in the case of low event rates
	signal EarlyPacketClear_S, EarlyPacketNotify_S : std_logic;
	signal EarlyPacketCyclesLimit_D                : unsigned(USB_EARLY_PACKET_WIDTH - 1 downto 0);

	-- register outputs for better behavior
	signal USBFifoWriteReg_SB, USBFifoPktEndReg_SB : std_logic;
	signal USBFifoAddressReg_D                     : std_logic_vector(1 downto 0);

	-- Double register configuration input, since it comes from a different clock domain (LogicClock), it
	-- needs to go through a double-flip-flop synchronizer to guarantee correctness.
	signal FX3ConfigSyncReg_D, FX3ConfigReg_D : tFX3Config;
begin
	writeCyclesCounter : entity work.ContinuousCounter
		generic map(
			SIZE => USB_BURST_WRITE_WIDTH)
		port map(
			Clock_CI     => Clock_CI,
			Reset_RI     => Reset_RI,
			Clear_SI     => '0',
			Enable_SI    => CyclesCount_S,
			DataLimit_DI => to_unsigned(USB_BURST_WRITE_CYCLES, USB_BURST_WRITE_WIDTH),
			Overflow_SO  => CyclesNotify_S,
			Data_DO      => open);

	EarlyPacketCyclesLimit_D <= FX3ConfigReg_D.EarlyPacketDelay_D * to_unsigned(USB_EARLY_PACKET_CYCLES, USB_EARLY_PACKET_CYCLES_WIDTH);

	earlyPacketCounter : entity work.ContinuousCounter
		generic map(
			SIZE              => USB_EARLY_PACKET_WIDTH,
			RESET_ON_OVERFLOW => false)
		port map(
			Clock_CI     => Clock_CI,
			Reset_RI     => Reset_RI,
			Clear_SI     => EarlyPacketClear_S,
			Enable_SI    => '1',
			DataLimit_DI => EarlyPacketCyclesLimit_D,
			Overflow_SO  => EarlyPacketNotify_S,
			Data_DO      => open);

	p_memoryless : process(State_DP, CyclesNotify_S, EarlyPacketNotify_S, USBFifoThread0Full_SI, USBFifoThread0AlmostFull_SI, USBFifoThread1Full_SI, USBFifoThread1AlmostFull_SI, InFifoControl_SI, FX3ConfigReg_D)
	begin
		State_DN <= State_DP;           -- Keep current state by default.

		CyclesCount_S <= '0';           -- Do not count up in the write-cycles counter.

		EarlyPacketClear_S <= '0';      -- Do not clear the early packet counter.

		USBFifoWriteReg_SB  <= '1';
		USBFifoPktEndReg_SB <= '1';
		USBFifoAddressReg_D <= USB_THREAD0;

		InFifoControl_SO.Read_S <= '0'; -- Don't read from input FIFO until we know we can write.

		case State_DP is
			when stIdle0 =>
				if FX3ConfigReg_D.Run_S = '1' and USBFifoThread0Full_SI = '0' then
					if EarlyPacketNotify_S = '1' then
						State_DN <= stPrepareEarlyPacket0;
					elsif InFifoControl_SI.AlmostEmpty_S = '0' then
						State_DN <= stPrepareWrite0;
					end if;
				end if;

			when stPrepareEarlyPacket0 =>
				if InFifoControl_SI.Empty_S = '0' then
					State_DN                <= stEarlyPacket0;
					InFifoControl_SO.Read_S <= '1';
					USBFifoWriteReg_SB      <= '0';
					USBFifoPktEndReg_SB     <= '0';
				end if;

			when stEarlyPacket0 =>
				USBFifoAddressReg_D <= USB_THREAD1; -- Access Thread 1.

				State_DN           <= stIdle1;
				EarlyPacketClear_S <= '1';

			when stPrepareWrite0 =>
				State_DN                <= stWriteFirst0;
				InFifoControl_SO.Read_S <= '1';
				USBFifoWriteReg_SB      <= '0';

			when stWriteFirst0 =>
				if USBFifoThread0AlmostFull_SI = '1' then
					State_DN <= stPrepareSwitch0;
				else
					State_DN <= stWriteMiddle0;
				end if;

				InFifoControl_SO.Read_S <= '1';
				USBFifoWriteReg_SB      <= '0';

			when stWriteMiddle0 =>
				if CyclesNotify_S = '1' then
					State_DN <= stWriteLast0;
				end if;

				CyclesCount_S <= '1';

				InFifoControl_SO.Read_S <= '1';
				USBFifoWriteReg_SB      <= '0';

			when stWriteLast0 =>
				if InFifoControl_SI.AlmostEmpty_S = '1' then
					State_DN <= stIdle0;
				else
					State_DN                <= stWriteFirst0;
					InFifoControl_SO.Read_S <= '1';
					USBFifoWriteReg_SB      <= '0';
				end if;

			when stPrepareSwitch0 =>
				if CyclesNotify_S = '1' then
					State_DN <= stSwitch0;
				end if;

				CyclesCount_S <= '1';

				InFifoControl_SO.Read_S <= '1';
				USBFifoWriteReg_SB      <= '0';

			when stSwitch0 =>
				USBFifoAddressReg_D <= USB_THREAD1; -- Access Thread 1.

				if InFifoControl_SI.AlmostEmpty_S = '1' or USBFifoThread1Full_SI = '1' then
					State_DN <= stIdle1;
				else
					State_DN                <= stWriteFirst1;
					InFifoControl_SO.Read_S <= '1';
					USBFifoWriteReg_SB      <= '0';
				end if;

				EarlyPacketClear_S <= '1';

			when stIdle1 =>
				USBFifoAddressReg_D <= USB_THREAD1; -- Access Thread 1.

				if FX3ConfigReg_D.Run_S = '1' and USBFifoThread1Full_SI = '0' then
					if EarlyPacketNotify_S = '1' then
						State_DN <= stPrepareEarlyPacket1;
					elsif InFifoControl_SI.AlmostEmpty_S = '0' then
						State_DN <= stPrepareWrite1;
					end if;
				end if;

			when stPrepareEarlyPacket1 =>
				USBFifoAddressReg_D <= USB_THREAD1; -- Access Thread 1.

				if InFifoControl_SI.Empty_S = '0' then
					State_DN                <= stEarlyPacket1;
					InFifoControl_SO.Read_S <= '1';
					USBFifoWriteReg_SB      <= '0';
					USBFifoPktEndReg_SB     <= '0';
				end if;

			when stEarlyPacket1 =>
				State_DN           <= stIdle0;
				EarlyPacketClear_S <= '1';

			when stPrepareWrite1 =>
				USBFifoAddressReg_D <= USB_THREAD1; -- Access Thread 1.

				State_DN                <= stWriteFirst1;
				InFifoControl_SO.Read_S <= '1';
				USBFifoWriteReg_SB      <= '0';

			when stWriteFirst1 =>
				USBFifoAddressReg_D <= USB_THREAD1; -- Access Thread 1.

				if USBFifoThread1AlmostFull_SI = '1' then
					State_DN <= stPrepareSwitch1;
				else
					State_DN <= stWriteMiddle1;
				end if;

				InFifoControl_SO.Read_S <= '1';
				USBFifoWriteReg_SB      <= '0';

			when stWriteMiddle1 =>
				USBFifoAddressReg_D <= USB_THREAD1; -- Access Thread 1.

				if CyclesNotify_S = '1' then
					State_DN <= stWriteLast1;
				end if;

				CyclesCount_S <= '1';

				InFifoControl_SO.Read_S <= '1';
				USBFifoWriteReg_SB      <= '0';

			when stWriteLast1 =>
				USBFifoAddressReg_D <= USB_THREAD1; -- Access Thread 1.

				if InFifoControl_SI.AlmostEmpty_S = '1' then
					State_DN <= stIdle1;
				else
					State_DN                <= stWriteFirst1;
					InFifoControl_SO.Read_S <= '1';
					USBFifoWriteReg_SB      <= '0';
				end if;

			when stPrepareSwitch1 =>
				USBFifoAddressReg_D <= USB_THREAD1; -- Access Thread 1.

				if CyclesNotify_S = '1' then
					State_DN <= stSwitch1;
				end if;

				CyclesCount_S <= '1';

				InFifoControl_SO.Read_S <= '1';
				USBFifoWriteReg_SB      <= '0';

			when stSwitch1 =>
				if InFifoControl_SI.AlmostEmpty_S = '1' or USBFifoThread0Full_SI = '1' then
					State_DN <= stIdle0;
				else
					State_DN                <= stWriteFirst0;
					InFifoControl_SO.Read_S <= '1';
					USBFifoWriteReg_SB      <= '0';
				end if;

				EarlyPacketClear_S <= '1';

			when others => null;
		end case;
	end process p_memoryless;

	-- Change state on clock edge (synchronous).
	p_memoryzing : process(Clock_CI, Reset_RI)
	begin
		if Reset_RI = '1' then          -- asynchronous reset (active-high for FPGAs)
			State_DP          <= stIdle0;
			USBFifoWrite_SBO  <= '1';
			USBFifoPktEnd_SBO <= '1';
			USBFifoAddress_DO <= USB_THREAD0;

			-- USB config from another clock domain.
			FX3ConfigReg_D     <= tFX3ConfigDefault;
			FX3ConfigSyncReg_D <= tFX3ConfigDefault;
		elsif rising_edge(Clock_CI) then
			State_DP          <= State_DN;
			USBFifoWrite_SBO  <= USBFifoWriteReg_SB;
			USBFifoPktEnd_SBO <= USBFifoPktEndReg_SB;
			USBFifoAddress_DO <= USBFifoAddressReg_D;

			-- USB config from another clock domain.
			FX3ConfigReg_D     <= FX3ConfigSyncReg_D;
			FX3ConfigSyncReg_D <= FX3Config_DI;
		end if;
	end process p_memoryzing;
end Behavioral;
