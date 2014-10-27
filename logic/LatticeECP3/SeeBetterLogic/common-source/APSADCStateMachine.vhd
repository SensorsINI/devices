library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.ceil;
use ieee.math_real.log2;
use work.EventCodes.all;
use work.FIFORecords.all;
use work.APSADCConfigRecords.all;

entity APSADCStateMachine is
	generic(
		ADC_CLOCK_FREQ    : integer;
		ADC_BUS_WIDTH     : integer;
		CHIP_SIZE_COLUMNS : integer;
		CHIP_SIZE_ROWS    : integer);
	port(
		Clock_CI               : in  std_logic; -- This clock must be 30MHz, use PLL to generate.
		Reset_RI               : in  std_logic; -- This reset must be synchronized to the above clock.

		-- Fifo output (to Multiplexer, must be a dual-clock FIFO)
		OutFifoControl_SI      : in  tFromFifoWriteSide;
		OutFifoControl_SO      : out tToFifoWriteSide;
		OutFifoData_DO         : out std_logic_vector(EVENT_WIDTH - 1 downto 0);

		APSChipRowSRClock_SO   : out std_logic;
		APSChipRowSRIn_SO      : out std_logic;
		APSChipColSRClock_SO   : out std_logic;
		APSChipColSRIn_SO      : out std_logic;
		APSChipColMode_DO      : out std_logic_vector(1 downto 0);
		APSChipTXGate_SBO      : out std_logic;

		APSADCData_DI          : in  std_logic_vector(ADC_BUS_WIDTH - 1 downto 0);
		APSADCOverflow_SI      : in  std_logic;
		APSADCClock_CO         : out std_logic;
		APSADCOutputEnable_SBO : out std_logic;
		APSADCStandby_SO       : out std_logic;

		-- Configuration input
		APSADCConfig_DI        : in  tAPSADCConfig);
end entity APSADCStateMachine;

architecture Behavioral of APSADCStateMachine is
	attribute syn_enum_encoding : string;

	type tColumnState is (stIdle, stWaitForADCStartup, stStartFrame, stEndFrame, stWaitFrameDelay, stRowReadStart, stRowReadWait);
	attribute syn_enum_encoding of tColumnState : type is "onehot";

	-- present and next state
	signal ColState_DP, ColState_DN : tColumnState;

	type tRowState is (stIdle, stRowDone, stRowSRInit, stRowSRInitTick, stRowSRFeedTick, stColSettleWait, stRowSettleWait, stRowWriteEvent, stRowFastJump);
	attribute syn_enum_encoding of tRowState : type is "onehot";

	-- present and next state
	signal RowState_DP, RowState_DN : tRowState;

	constant CHIP_REG_SIZE_COLUMNS : integer := 1 + CHIP_SIZE_COLUMNS + 1; -- One bit more on each side, for three-bit code.
	constant CHIP_REG_SIZE_ROWS    : integer := CHIP_SIZE_ROWS;

	constant ADC_STARTUP_CYCLES      : integer := 45; -- At 30MHz, wait 1.5 microseconds.
	constant ADC_STARTUP_CYCLES_SIZE : integer := integer(ceil(log2(real(ADC_STARTUP_CYCLES))));

	constant COLMODE_NULL   : std_logic_vector(1 downto 0) := "00";
	constant COLMODE_READA  : std_logic_vector(1 downto 0) := "01";
	constant COLMODE_READB  : std_logic_vector(1 downto 0) := "10";
	constant COLMODE_RESETA : std_logic_vector(1 downto 0) := "11";

	constant ADC_CLOCK_FREQ_SIZE     : integer := integer(ceil(log2(real(ADC_CLOCK_FREQ + 1))));
	constant EXPOSUREDELAY_TIME_SIZE : integer := ADC_CLOCK_FREQ_SIZE + EXPOSUREDELAY_SIZE;

	-- Take note if the ADC is running already or not. If not, it has to be started.
	signal ADCRunning_SP, ADCRunning_SN : std_logic;

	signal ADCStartupCount_S, ADCStartupDone_S : std_logic;

	-- Inputs are in microseconds, so we need to transform them with the clock frequency to get cycles.
	signal ExposureTimeCycles_D   : unsigned(EXPOSUREDELAY_TIME_SIZE - 1 downto 0);
	signal FrameDelayTimeCycles_D : unsigned(EXPOSUREDELAY_TIME_SIZE - 1 downto 0);

	-- Use one counter for both exposure and frame delay times, they cannot happen at the same time.
	signal ExposureDelayClear_S, ExposureDelayDone_S : std_logic;
	signal ExposureDelayLimit_D                      : unsigned(EXPOSUREDELAY_TIME_SIZE - 1 downto 0);

	-- Reset time counter (bigger to allow for long resets if needed).
	signal ResetTimeCount_S, ResetTimeDone_S : std_logic;

	-- Use one counter for both column and row settle times, they cannot happen at the same time.
	signal SettleTimesCount_S, SettleTimesDone_S : std_logic;
	signal SettleTimesLimit_D                    : unsigned(SETTLETIMES_SIZE - 1 downto 0);

	-- Column and row read counters.
	signal ColumnReadAPositionZero_S, ColumnReadAPositionInc_S : std_logic;
	signal ColumnReadAPosition_D                               : unsigned(CHIP_SIZE_COLUMNS_WIDTH - 1 downto 0);
	signal ColumnReadBPositionZero_S, ColumnReadBPositionInc_S : std_logic;
	signal ColumnReadBPosition_D                               : unsigned(CHIP_SIZE_COLUMNS_WIDTH - 1 downto 0);
	signal RowReadPositionZero_S, RowReadPositionInc_S         : std_logic;
	signal RowReadPosition_D                                   : unsigned(CHIP_SIZE_ROWS_WIDTH - 1 downto 0);

	-- Communication between column and row state machines. Done through a register for full decoupling.
	signal RowReadStart_SP, RowReadStart_SN : std_logic;
	signal RowReadDone_SP, RowReadDone_SN   : std_logic;

	-- Register outputs to FIFO.
	signal OutFifoWriteReg_S, OutFifoWriteRegCol_S, OutFifoWriteRegRow_S                : std_logic;
	signal OutFifoDataRegEnable_S, OutFifoDataRegColEnable_S, OutFifoDataRegRowEnable_S : std_logic;
	signal OutFifoDataReg_D, OutFifoDataRegCol_D, OutFifoDataRegRow_D                   : std_logic_vector(EVENT_WIDTH - 1 downto 0);

	-- Register all outputs to ADC and chip for clean transitions.
	signal APSChipRowSRClockReg_S, APSChipRowSRInReg_S  : std_logic;
	signal APSChipColSRClockReg_S, APSChipColSRInReg_S  : std_logic;
	signal APSChipColModeReg_DP, APSChipColModeReg_DN   : std_logic_vector(1 downto 0);
	signal APSChipTXGateReg_S                           : std_logic;
	signal APSADCOutputEnableReg_SB, APSADCStandbyReg_S : std_logic;

	-- Double register configuration input, since it comes from a different clock domain (LogicClock), it
	-- needs to go through a double-flip-flop synchronizer to guarantee correctness.
	signal APSADCConfigSyncReg_D, APSADCConfigReg_D     : tAPSADCConfig;
	signal CurrentColumnAValid_S, CurrentColumnBValid_S : std_logic;
	signal CurrentColumnValid_S                         : std_logic;
	signal CurrentRowValid_S                            : std_logic;
	signal CurrentReadValid_S                           : std_logic;
begin
	-- Forward 30MHz clock directly to external ADC.
	APSADCClock_CO <= Clock_CI;

	adcStartupCounter : entity work.ContinuousCounter
		generic map(
			SIZE => ADC_STARTUP_CYCLES_SIZE)
		port map(
			Clock_CI     => Clock_CI,
			Reset_RI     => Reset_RI,
			Clear_SI     => '0',
			Enable_SI    => ADCStartupCount_S,
			DataLimit_DI => to_unsigned(ADC_STARTUP_CYCLES - 1, ADC_STARTUP_CYCLES_SIZE),
			Overflow_SO  => ADCStartupDone_S,
			Data_DO      => open);

	-- Multiply to get cycles from microseconds.
	ExposureTimeCycles_D   <= APSADCConfigReg_D.Exposure_D * to_unsigned(ADC_CLOCK_FREQ, ADC_CLOCK_FREQ_SIZE);
	FrameDelayTimeCycles_D <= APSADCConfigReg_D.FrameDelay_D * to_unsigned(ADC_CLOCK_FREQ, ADC_CLOCK_FREQ_SIZE);

	exposureDelayCounter : entity work.ContinuousCounter
		generic map(
			SIZE              => EXPOSUREDELAY_TIME_SIZE,
			RESET_ON_OVERFLOW => false)
		port map(
			Clock_CI     => Clock_CI,
			Reset_RI     => Reset_RI,
			Clear_SI     => ExposureDelayClear_S,
			Enable_SI    => '1',
			DataLimit_DI => ExposureDelayLimit_D,
			Overflow_SO  => ExposureDelayDone_S,
			Data_DO      => open);

	colReadAPosition : entity work.ContinuousCounter
		generic map(
			SIZE              => CHIP_SIZE_COLUMNS_WIDTH,
			GENERATE_OVERFLOW => false)
		port map(
			Clock_CI     => Clock_CI,
			Reset_RI     => Reset_RI,
			Clear_SI     => ColumnReadAPositionZero_S,
			Enable_SI    => ColumnReadAPositionInc_S,
			DataLimit_DI => to_unsigned(CHIP_SIZE_COLUMNS, CHIP_SIZE_COLUMNS_WIDTH),
			Overflow_SO  => open,
			Data_DO      => ColumnReadAPosition_D);

	colReadBPosition : entity work.ContinuousCounter
		generic map(
			SIZE              => CHIP_SIZE_COLUMNS_WIDTH,
			GENERATE_OVERFLOW => false)
		port map(
			Clock_CI     => Clock_CI,
			Reset_RI     => Reset_RI,
			Clear_SI     => ColumnReadBPositionZero_S,
			Enable_SI    => ColumnReadBPositionInc_S,
			DataLimit_DI => to_unsigned(CHIP_SIZE_COLUMNS, CHIP_SIZE_COLUMNS_WIDTH),
			Overflow_SO  => open,
			Data_DO      => ColumnReadBPosition_D);

	rowReadPosition : entity work.ContinuousCounter
		generic map(
			SIZE              => CHIP_SIZE_ROWS_WIDTH,
			GENERATE_OVERFLOW => false)
		port map(
			Clock_CI     => Clock_CI,
			Reset_RI     => Reset_RI,
			Clear_SI     => RowReadPositionZero_S,
			Enable_SI    => RowReadPositionInc_S,
			DataLimit_DI => to_unsigned(CHIP_SIZE_ROWS, CHIP_SIZE_ROWS_WIDTH),
			Overflow_SO  => open,
			Data_DO      => RowReadPosition_D);

	resetTimeCounter : entity work.ContinuousCounter
		generic map(
			SIZE => RESETTIME_SIZE)
		port map(
			Clock_CI     => Clock_CI,
			Reset_RI     => Reset_RI,
			Clear_SI     => '0',
			Enable_SI    => ResetTimeCount_S,
			DataLimit_DI => APSADCConfigReg_D.ResetSettle_D,
			Overflow_SO  => ResetTimeDone_S,
			Data_DO      => open);

	settleTimesCounter : entity work.ContinuousCounter
		generic map(
			SIZE => SETTLETIMES_SIZE)
		port map(
			Clock_CI     => Clock_CI,
			Reset_RI     => Reset_RI,
			Clear_SI     => '0',
			Enable_SI    => SettleTimesCount_S,
			DataLimit_DI => SettleTimesLimit_D,
			Overflow_SO  => SettleTimesDone_S,
			Data_DO      => open);

	columnMainStateMachine : process(ColState_DP, ADCRunning_SP, ADCStartupDone_S, APSADCConfigReg_D, ExposureDelayDone_S, ExposureTimeCycles_D, FrameDelayTimeCycles_D, RowReadDone_SP)
	begin
		ColState_DN <= ColState_DP;     -- Keep current state by default.

		OutFifoWriteRegCol_S      <= '0';
		OutFifoDataRegColEnable_S <= '0';
		OutFifoDataRegCol_D       <= (others => '0');

		ADCRunning_SN     <= ADCRunning_SP;
		ADCStartupCount_S <= '0';

		-- Keep ADC powered and OE by default, the Idle (start) state will
		-- then negotiate the necessary settings, and when we're out of Idle,
		-- they are always on anyway.
		APSADCOutputEnableReg_SB <= '0';
		APSADCStandbyReg_S       <= '0';

		APSChipColSRClockReg_S <= '0';
		APSChipColSRInReg_S    <= '0';

		APSChipColModeReg_DN <= COLMODE_NULL;
		APSChipTXGateReg_S   <= '0';

		-- By default keep exposure/frame delay counter cleared and inactive.
		ExposureDelayClear_S <= '0';
		ExposureDelayLimit_D <= ExposureTimeCycles_D;

		-- Colum counters.
		ColumnReadAPositionZero_S <= '0';
		ColumnReadAPositionInc_S  <= '0';
		ColumnReadBPositionZero_S <= '0';
		ColumnReadBPositionInc_S  <= '0';

		-- Reset time counter.
		ResetTimeCount_S <= '0';

		-- Row SM communication.
		RowReadStart_SN <= '0';

		case ColState_DP is
			when stIdle =>
				if APSADCConfigReg_D.Run_S = '1' then
					-- We want to take samples (picture or video), so the ADC has to be running.
					if ADCRunning_SP = '0' then
						ColState_DN <= stWaitForADCStartup;
					else
						ColState_DN <= stStartFrame;
					end if;
				else
					-- Turn ADC off when not running, unless low-latency camera mode is selected.
					if APSADCConfigReg_D.Mode_D /= APSADC_MODE_CAMERA_LOWLATENCY then
						APSADCOutputEnableReg_SB <= '1';
						APSADCStandbyReg_S       <= '1';
						ADCRunning_SN            <= '0';
					end if;
				end if;

			when stWaitForADCStartup =>
				-- Wait 1.5 microseconds for ADC to start up and be ready for precise conversions.
				if ADCStartupDone_S = '1' then
					ColState_DN   <= stStartFrame;
					ADCRunning_SN <= '1';
				end if;

				ADCStartupCount_S <= '1';

			when stStartFrame   =>
			when stRowReadStart =>
				RowReadStart_SN <= '1';
				ColState_DN     <= stRowReadWait;

			when stRowReadWait =>
				if RowReadDone_SP = '1' then
				end if;

			when stEndFrame =>
				-- Setup exposureDelay counter to count frame delay instead of exposure.
				ExposureDelayLimit_D <= FrameDelayTimeCycles_D;
				ExposureDelayClear_S <= '1';

				ColState_DN <= stWaitFrameDelay;

			when stWaitFrameDelay =>
				-- Wait until enough time has passed between frames.
				ExposureDelayLimit_D <= FrameDelayTimeCycles_D;

				if ExposureDelayDone_S = '1' then
					ColState_DN <= stIdle;
				end if;

			when others => null;
		end case;
	end process columnMainStateMachine;

	-- Concurrently calculate if the current pixel has to be read out or not.
	-- If not (like with ROI), we can just fast jump that row.
	CurrentColumnAValid_S <= '1' when (ColumnReadAPosition_D >= APSADCConfigReg_D.StartColumn_D and ColumnReadAPosition_D <= APSADCConfigReg_D.EndColumn_D) else '0';
	CurrentColumnBValid_S <= '1' when (ColumnReadBPosition_D >= APSADCConfigReg_D.StartColumn_D and ColumnReadBPosition_D <= APSADCConfigReg_D.EndColumn_D) else '0';
	CurrentColumnValid_S  <= '1' when ((APSChipColModeReg_DP = COLMODE_READA and CurrentColumnAValid_S = '1') or (APSChipColModeReg_DP = COLMODE_READB and CurrentColumnBValid_S = '1')) else '0';
	CurrentRowValid_S     <= '1' when (RowReadPosition_D >= APSADCConfigReg_D.StartRow_D and RowReadPosition_D <= APSADCConfigReg_D.EndRow_D) else '0';
	CurrentReadValid_S    <= CurrentColumnValid_S and CurrentRowValid_S;

	rowReadStateMachine : process(RowState_DP, APSADCConfigReg_D, APSADCData_DI, APSChipColModeReg_DP, CurrentReadValid_S, OutFifoControl_SI.Full_S, RowReadStart_SP, SettleTimesDone_S)
	begin
		RowState_DN <= RowState_DP;

		OutFifoWriteRegRow_S      <= '0';
		OutFifoDataRegRowEnable_S <= '0';
		OutFifoDataRegRow_D       <= (others => '0');

		APSChipRowSRClockReg_S <= '0';
		APSChipRowSRInReg_S    <= '0';

		-- Row counters.
		RowReadPositionZero_S <= '0';
		RowReadPositionInc_S  <= '0';

		-- Settle times counter.
		SettleTimesLimit_D <= (others => '0');
		SettleTimesCount_S <= '0';

		-- Column SM communication.
		RowReadDone_SN <= '0';

		case RowState_DP is
			when stIdle =>
				-- Wait until the main column state machine signals us to do a row read.
				if RowReadStart_SP = '1' then
					RowState_DN <= stColSettleWait;
				end if;

			when stColSettleWait =>
				-- Wait for the column selection to be valid. We do this here so we don't have to duplicate
				-- this code in every column state inside the main column state machine.
				if SettleTimesDone_S = '1' then
					RowState_DN <= stRowSRInit;
				end if;

				SettleTimesCount_S <= '1';

				-- Select proper source for column settle time.
				SettleTimesLimit_D <= APSADCConfigReg_D.ColumnSettle_D;

			when stRowSRInit =>
				APSChipRowSRClockReg_S <= '0';
				APSChipRowSRInReg_S    <= '1';

				-- Write event only if FIFO has place, else wait.
				if OutFifoControl_SI.Full_S = '0' then
					if APSChipColModeReg_DP = COLMODE_READA then
						OutFifoDataRegRow_D <= EVENT_CODE_SPECIAL & EVENT_CODE_SPECIAL_APS_STARTRESETCOL;
					else
						OutFifoDataRegRow_D <= EVENT_CODE_SPECIAL & EVENT_CODE_SPECIAL_APS_STARTSIGNALCOL;
					end if;
					OutFifoDataRegRowEnable_S <= '1';

					RowState_DN          <= stRowSRInitTick;
					RowReadPositionInc_S <= '1';
				end if;

			when stRowSRInitTick =>
				APSChipRowSRClockReg_S <= '1';
				APSChipRowSRInReg_S    <= '1';

				if CurrentReadValid_S = '1' then
					RowState_DN <= stRowSettleWait;
				else
					RowState_DN <= stRowFastJump;
				end if;

			when stRowSRFeedTick =>
				APSChipRowSRClockReg_S <= '1';
				APSChipRowSRInReg_S    <= '0';

				if CurrentReadValid_S = '1' then
					RowState_DN <= stRowSettleWait;
				else
					RowState_DN <= stRowFastJump;
				end if;

			when stRowSettleWait =>
				-- Wait for the row selection to be valid.
				if SettleTimesDone_S = '1' then
					RowState_DN <= stRowWriteEvent;
				end if;

				SettleTimesCount_S <= '1';

				-- Select proper source for row settle time.
				SettleTimesLimit_D <= APSADCConfigReg_D.RowSettle_D;

			when stRowWriteEvent =>
				-- Write event only if FIFO has place, else wait.
				if OutFifoControl_SI.Full_S = '0' then
					-- This is only a 10-bit ADC, so we pad with two zeros.
					OutFifoDataRegRow_D       <= EVENT_CODE_ADC_SAMPLE & "00" & APSADCData_DI;
					OutFifoDataRegRowEnable_S <= '1';

					RowState_DN          <= stRowSRFeedTick;
					RowReadPositionInc_S <= '1';
				end if;

			when stRowFastJump =>
				if APSADCConfigReg_D.ROIZeroPad = '1' then
					-- Write event only if FIFO has place, else wait.
					if OutFifoControl_SI.Full_S = '0' then
						-- Send fake ADC value of all zeros.
						OutFifoDataRegRow_D       <= EVENT_CODE_ADC_SAMPLE & "000000000000";
						OutFifoDataRegRowEnable_S <= '1';

						RowState_DN          <= stRowSRFeedTick;
						RowReadPositionInc_S <= '1';
					end if;
				else
					RowState_DN          <= stRowSRFeedTick;
					RowReadPositionInc_S <= '1';
				end if;

			when stRowDone =>
				-- Write event only if FIFO has place, else wait.
				if OutFifoControl_SI.Full_S = '0' then
					OutFifoDataRegRow_D       <= EVENT_CODE_SPECIAL & EVENT_CODE_SPECIAL_APS_ENDCOL;
					OutFifoDataRegRowEnable_S <= '1';

					RowReadDone_SN <= '1';
					RowState_DN    <= stIdle;
				end if;

			when others => null;
		end case;
	end process rowReadStateMachine;

	-- FIFO output can be driven by both the column or the row state machines.
	-- Care must be taken to never have both at the same time output meaningful data.
	OutFifoWriteReg_S      <= OutFifoWriteRegCol_S or OutFifoWriteRegRow_S;
	OutFifoDataRegEnable_S <= OutFifoDataRegColEnable_S or OutFifoDataRegRowEnable_S;
	OutFifoDataReg_D       <= OutFifoDataRegCol_D or OutFifoDataRegRow_D;

	outputDataRegister : entity work.SimpleRegister
		generic map(
			SIZE => EVENT_WIDTH)
		port map(
			Clock_CI  => Clock_CI,
			Reset_RI  => Reset_RI,
			Enable_SI => OutFifoDataRegEnable_S,
			Input_SI  => OutFifoDataReg_D,
			Output_SO => OutFifoData_DO);

	-- Change state on clock edge (synchronous).
	p_memoryzing : process(Clock_CI, Reset_RI)
	begin
		if Reset_RI = '1' then          -- asynchronous reset (active-high for FPGAs)
			ColState_DP <= stIdle;
			RowState_DP <= stIdle;

			ADCRunning_SP <= '0';

			RowReadStart_SP <= '0';
			RowReadDone_SP  <= '0';

			OutFifoControl_SO.Write_S <= '0';

			APSChipRowSRClock_SO <= '0';
			APSChipRowSRIn_SO    <= '0';
			APSChipColSRClock_SO <= '0';
			APSChipColSRIn_SO    <= '0';
			APSChipColModeReg_DP <= COLMODE_NULL;
			APSChipTXGate_SBO    <= '1';

			APSADCOutputEnable_SBO <= '1';
			APSADCStandby_SO       <= '1';

			-- APS ADC config from another clock domain.
			APSADCConfigReg_D     <= tAPSADCConfigDefault;
			APSADCConfigSyncReg_D <= tAPSADCConfigDefault;
		elsif rising_edge(Clock_CI) then
			ColState_DP <= ColState_DN;
			RowState_DP <= RowState_DN;

			ADCRunning_SP <= ADCRunning_SN;

			RowReadStart_SP <= RowReadStart_SN;
			RowReadDone_SP  <= RowReadDone_SN;

			OutFifoControl_SO.Write_S <= OutFifoWriteReg_S;

			APSChipRowSRClock_SO <= APSChipRowSRClockReg_S;
			APSChipRowSRIn_SO    <= APSChipRowSRInReg_S;
			APSChipColSRClock_SO <= APSChipColSRClockReg_S;
			APSChipColSRIn_SO    <= APSChipColSRInReg_S;
			APSChipColModeReg_DP <= APSChipColModeReg_DN;
			APSChipTXGate_SBO    <= not APSChipTXGateReg_S;

			APSADCOutputEnable_SBO <= APSADCOutputEnableReg_SB;
			APSADCStandby_SO       <= APSADCStandbyReg_S;

			-- APS ADC config from another clock domain.
			APSADCConfigReg_D     <= APSADCConfigSyncReg_D;
			APSADCConfigSyncReg_D <= APSADCConfig_DI;
		end if;
	end process p_memoryzing;

	-- The output of this register goes to an intermediate signal, since we need to access it
	-- inside this module. That's not possible with 'out' signal directly.
	APSChipColMode_DO <= APSChipColModeReg_DP;
end architecture Behavioral;
