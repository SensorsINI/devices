library IEEE;
use IEEE.STD_LOGIC_1164.all;
use work.Settings.all;
use work.FIFORecords.all;

entity TopLevel is
	port (
		USBClock_CI : in std_logic;
		Reset_RI	: in std_logic;

		LogicRun_AI			: in  std_logic;
		DVSRun_AI			: in  std_logic;
		APSRun_AI			: in  std_logic;
		IMURun_AI			: in  std_logic;
		SPI_SlaveSelect_ABI : in  std_logic;
		SPI_Clock_AI		: in  std_logic;
		SPI_MOSI_AI			: in  std_logic;
		SPI_MISO_DO			: out std_logic;
		BiasEnable_SI		: in  std_logic;
		BiasDiagSelect_SI	: in  std_logic;

		USBFifoData_DO				: out std_logic_vector(USB_FIFO_WIDTH-1 downto 0);
		USBFifoWrite_SBO			: out std_logic;
		USBFifoRead_SBO				: out std_logic;
		USBFifoPktEnd_SBO			: out std_logic;
		USBFifoAddress_DO			: out std_logic_vector(1 downto 0);
		USBFifoFullFlag_SI			: in  std_logic;
		USBFifoProgrammableFlag_SBI : in  std_logic;

		LED1_SO : out std_logic;
		LED2_SO : out std_logic;
		LED3_SO : out std_logic;

		ChipBiasEnable_SO	  : out std_logic;
		ChipBiasDiagSelect_SO : out std_logic;
		--ChipBiasBitOut_DI : in std_logic;

		DVSAERData_DI	: in  std_logic_vector(AER_BUS_WIDTH-1 downto 0);
		DVSAERReq_ABI	: in  std_logic;
		DVSAERAck_SBO	: out std_logic;
		DVSAERReset_SBO : out std_logic;

		APSChipRowSRClock_SO : out std_logic;
		APSChipRowSRIn_SO	 : out std_logic;
		APSChipColSRClock_SO : out std_logic;
		APSChipColSRIn_SO	 : out std_logic;
		APSChipColMode_DO	 : out std_logic_vector(1 downto 0);
		APSChipTXGate_SO	 : out std_logic;

		APSADCData_DI		   : in	 std_logic_vector(ADC_BUS_WIDTH-1 downto 0);
		APSADCOverflow_SI	   : in	 std_logic;
		APSADCClock_CO		   : out std_logic;
		APSADCOutputEnable_SBO : out std_logic;
		APSADCStandby_SO	   : out std_logic;

		IMUClock_ZO		: inout std_logic;	-- this is inout because it must be tristateable
		IMUData_ZIO		: inout std_logic;
		IMUInterrupt_AI : in	std_logic;

		SyncOutClock_CO	 : out std_logic;
		SyncOutSwitch_AI : in  std_logic;
		SyncOutSignal_SO : out std_logic;
		SyncInClock_AI	 : in  std_logic;
		SyncInSwitch_AI	 : in  std_logic;
		SyncInSignal_AI	 : in  std_logic);
end TopLevel;

architecture Structural of TopLevel is
	component USBClockSynchronizer is
		port (
			USBClock_CI					   : in	 std_logic;
			Reset_RI					   : in	 std_logic;
			ResetSync_RO				   : out std_logic;
			USBFifoFullFlag_SI			   : in	 std_logic;
			USBFifoFullFlagSync_SO		   : out std_logic;
			USBFifoProgrammableFlag_SI	   : in	 std_logic;
			USBFifoProgrammableFlagSync_SO : out std_logic);
	end component USBClockSynchronizer;

	component LogicClockSynchronizer is
		port (
			LogicClock_CI		 : in  std_logic;
			Reset_RI			 : in  std_logic;
			ResetSync_RO		 : out std_logic;
			LogicRun_SI			 : in  std_logic;
			LogicRunSync_SO		 : out std_logic;
			DVSRun_SI			 : in  std_logic;
			DVSRunSync_SO		 : out std_logic;
			APSRun_SI			 : in  std_logic;
			APSRunSync_SO		 : out std_logic;
			IMURun_SI			 : in  std_logic;
			IMURunSync_SO		 : out std_logic;
			DVSAERReq_SBI		 : in  std_logic;
			DVSAERReqSync_SBO	 : out std_logic;
			IMUInterrupt_SI		 : in  std_logic;
			IMUInterruptSync_SO	 : out std_logic;
			SyncOutSwitch_SI	 : in  std_logic;
			SyncOutSwitchSync_SO : out std_logic;
			SyncInClock_CI		 : in  std_logic;
			SyncInClockSync_CO	 : out std_logic;
			SyncInSwitch_SI		 : in  std_logic;
			SyncInSwitchSync_SO	 : out std_logic;
			SyncInSignal_SI		 : in  std_logic;
			SyncInSignalSync_SO	 : out std_logic);
	end component LogicClockSynchronizer;

	component FX2Statemachine is
		port (
			Clock_CI				: in  std_logic;
			Reset_RI				: in  std_logic;
			USBFifoEP6Full_SI		: in  std_logic;
			USBFifoEP6AlmostFull_SI : in  std_logic;
			USBFifoWrite_SBO		: out std_logic;
			USBFifoPktEnd_SBO		: out std_logic;
			InFifo_I				: in  tFromFifoReadSide;
			InFifo_O				: out tToFifoReadSide);
	end component FX2Statemachine;

	component MultiplexerStateMachine is
		port (
			Clock_CI		  : in	std_logic;
			Reset_RI		  : in	std_logic;
			Run_SI			  : in	std_logic;
			TimestampReset_SI : in	std_logic;
			OutFifo_I		  : in	tFromFifoWriteSide;
			OutFifo_O		  : out tToFifoWriteSide;
			DVSAERFifo_I	  : in	tFromFifoReadSide;
			DVSAERFifo_O	  : out tToFifoReadSide;
			APSADCFifo_I	  : in	tFromFifoReadSide;
			APSADCFifo_O	  : out tToFifoReadSide;
			IMUFifo_I		  : in	tFromFifoReadSide;
			IMUFifo_O		  : out tToFifoReadSide;
			ExtTriggerFifo_I  : in	tFromFifoReadSide;
			ExtTriggerFifo_O  : out tToFifoReadSide);
	end component MultiplexerStateMachine;

	component DVSAERStateMachine is
		port (
			Clock_CI		: in  std_logic;
			Reset_RI		: in  std_logic;
			DVSRun_SI		: in  std_logic;
			OutFifo_I		: in  tFromFifoWriteSide;
			OutFifo_O		: out tToFifoWriteSide;
			DVSAERData_DI	: in  std_logic_vector(AER_BUS_WIDTH-1 downto 0);
			DVSAERReq_SBI	: in  std_logic;
			DVSAERAck_SBO	: out std_logic;
			DVSAERReset_SBO : out std_logic);
	end component DVSAERStateMachine;

	component IMUStateMachine is
		port (
			Clock_CI		: in	std_logic;
			Reset_RI		: in	std_logic;
			IMURun_SI		: in	std_logic;
			OutFifo_I		: in	tFromFifoWriteSide;
			OutFifo_O		: out	tToFifoWriteSide;
			IMUClock_ZO		: inout std_logic;
			IMUData_ZIO		: inout std_logic;
			IMUInterrupt_SI : in	std_logic);
	end component IMUStateMachine;

	component APSADCStateMachine is
		port (
			Clock_CI			   : in	 std_logic;
			Reset_RI			   : in	 std_logic;
			APSRun_SI			   : in	 std_logic;
			OutFifo_I			   : in	 tFromFifoWriteSide;
			OutFifo_O			   : out tToFifoWriteSide;
			APSChipRowSRClock_SO   : out std_logic;
			APSChipRowSRIn_SO	   : out std_logic;
			APSChipColSRClock_SO   : out std_logic;
			APSChipColSRIn_SO	   : out std_logic;
			APSChipColMode_DO	   : out std_logic_vector(1 downto 0);
			APSChipTXGate_SO	   : out std_logic;
			APSADCData_DI		   : in	 std_logic_vector(ADC_BUS_WIDTH-1 downto 0);
			APSADCOverflow_SI	   : in	 std_logic;
			APSADCClock_CO		   : out std_logic;
			APSADCOutputEnable_SBO : out std_logic;
			APSADCStandby_SO	   : out std_logic);
	end component APSADCStateMachine;

	component ExtTriggerStateMachine is
		port (
			Clock_CI			: in  std_logic;
			Reset_RI			: in  std_logic;
			ExtTriggerRun_SI	: in  std_logic;
			OutFifo_I			: in  tFromFifoWriteSide;
			OutFifo_O			: out tToFifoWriteSide;
			ExtTriggerSwitch_SI : in  std_logic;
			ExtTriggerSignal_SI : in  std_logic);
	end component ExtTriggerStateMachine;

	component FIFODualClock is
		generic (
			DATA_WIDTH		  : integer;
			DATA_DEPTH		  : integer;
			EMPTY_FLAG		  : integer;
			ALMOST_EMPTY_FLAG : integer;
			FULL_FLAG		  : integer;
			ALMOST_FULL_FLAG  : integer);
		port (
			Reset_RI   : in	 std_logic;
			WrClock_CI : in	 std_logic;
			RdClock_CI : in	 std_logic;
			Fifo_I	   : in	 tToFifo(WriteSide(Data_D(DATA_WIDTH-1 downto 0)));
			Fifo_O	   : out tFromFifo(ReadSide(Data_D(DATA_WIDTH-1 downto 0))));
	end component FIFODualClock;

	component FIFO is
		generic (
			DATA_WIDTH		  : integer;
			DATA_DEPTH		  : integer;
			EMPTY_FLAG		  : integer;
			ALMOST_EMPTY_FLAG : integer;
			FULL_FLAG		  : integer;
			ALMOST_FULL_FLAG  : integer);
		port (
			Clock_CI : in  std_logic;
			Reset_RI : in  std_logic;
			Fifo_I	 : in  tToFifo(WriteSide(Data_D(DATA_WIDTH-1 downto 0)));
			Fifo_O	 : out tFromFifo(ReadSide(Data_D(DATA_WIDTH-1 downto 0))));
	end component FIFO;

	component PLL is
		generic (
			CLOCK_FREQ	   : integer;
			OUT_CLOCK_FREQ : integer);
		port (
			Clock_CI	: in  std_logic;
			Reset_RI	: in  std_logic;
			OutClock_CO : out std_logic);
	end component PLL;

	signal USBReset_R	: std_logic;
	signal LogicClock_C : std_logic;
	signal LogicReset_R : std_logic;

	signal USBFifoFullFlagSync_S, USBFifoProgrammableFlagSync_S							  : std_logic;
	signal LogicRunSync_S, DVSRunSync_S, APSRunSync_S, IMURunSync_S						  : std_logic;
	signal DVSAERReqSync_SB, IMUInterruptSync_S											  : std_logic;
	signal SyncOutSwitchSync_S, SyncInClockSync_C, SyncInSwitchSync_S, SyncInSignalSync_S : std_logic;

	signal DVSRun_S, APSRun_S, IMURun_S, ExtTriggerRun_S						 : std_logic;
	signal DVSFifoReset_R, APSFifoReset_R, IMUFifoReset_R, ExtTriggerFifoReset_R : std_logic;

	signal LogicUSBFifo_I : tToFifo(WriteSide(Data_D(USB_FIFO_WIDTH-1 downto 0)));
	signal LogicUSBFifo_O : tFromFifo(ReadSide(Data_D(USB_FIFO_WIDTH-1 downto 0)));

	signal DVSAERFifo_I : tToFifo(WriteSide(Data_D(EVENT_WIDTH-1 downto 0)));
	signal DVSAERFifo_O : tFromFifo(ReadSide(Data_D(EVENT_WIDTH-1 downto 0)));

	signal APSADCFifo_I : tToFifo(WriteSide(Data_D(EVENT_WIDTH-1 downto 0)));
	signal APSADCFifo_O : tFromFifo(ReadSide(Data_D(EVENT_WIDTH-1 downto 0)));

	signal IMUFifo_I : tToFifo(WriteSide(Data_D(EVENT_WIDTH-1 downto 0)));
	signal IMUFifo_O : tFromFifo(ReadSide(Data_D(EVENT_WIDTH-1 downto 0)));

	signal ExtTriggerFifo_I : tToFifo(WriteSide(Data_D(EVENT_WIDTH-1 downto 0)));
	signal ExtTriggerFifo_O : tFromFifo(ReadSide(Data_D(EVENT_WIDTH-1 downto 0)));
begin
	-- First: synchronize all USB-related inputs to the USB clock.
	syncInputsToUSBClock : USBClockSynchronizer
		port map (
			USBClock_CI					   => USBClock_CI,
			Reset_RI					   => Reset_RI,
			ResetSync_RO				   => USBReset_R,
			USBFifoFullFlag_SI			   => USBFifoFullFlag_SI,
			USBFifoFullFlagSync_SO		   => USBFifoFullFlagSync_S,
			USBFifoProgrammableFlag_SI	   => not USBFifoProgrammableFlag_SBI,
			USBFifoProgrammableFlagSync_SO => USBFifoProgrammableFlagSync_S);

	-- Second: synchronize all logic-related inputs to the logic clock.
	syncInputsToLogicClock : LogicClockSynchronizer
		port map (
			LogicClock_CI		 => LogicClock_C,
			Reset_RI			 => Reset_RI,
			ResetSync_RO		 => LogicReset_R,
			LogicRun_SI			 => LogicRun_AI,
			LogicRunSync_SO		 => LogicRunSync_S,
			DVSRun_SI			 => DVSRun_AI,
			DVSRunSync_SO		 => DVSRunSync_S,
			APSRun_SI			 => APSRun_AI,
			APSRunSync_SO		 => APSRunSync_S,
			IMURun_SI			 => IMURun_AI,
			IMURunSync_SO		 => IMURunSync_S,
			DVSAERReq_SBI		 => DVSAERReq_ABI,
			DVSAERReqSync_SBO	 => DVSAERReqSync_SB,
			IMUInterrupt_SI		 => IMUInterrupt_AI,
			IMUInterruptSync_SO	 => IMUInterruptSync_S,
			SyncOutSwitch_SI	 => SyncOutSwitch_AI,
			SyncOutSwitchSync_SO => SyncOutSwitchSync_S,
			SyncInClock_CI		 => SyncInClock_AI,
			SyncInClockSync_CO	 => SyncInClockSync_C,
			SyncInSwitch_SI		 => SyncInSwitch_AI,
			SyncInSwitchSync_SO	 => SyncInSwitchSync_S,
			SyncInSignal_SI		 => SyncInSignal_AI,
			SyncInSignalSync_SO	 => SyncInSignalSync_S);

	-- Third: set all constant outputs.
	USBFifoRead_SBO		  <= '1';  -- We never read from the USB data path (active-low).
	USBFifoAddress_DO	  <= "10";		-- Always write to EP6.
	USBFifoData_DO		  <= LogicUSBFifo_O.ReadSide.Data_D;
	ChipBiasEnable_SO	  <= BiasEnable_SI;		 -- Direct bypass.
	ChipBiasDiagSelect_SO <= BiasDiagSelect_SI;	 -- Direct bypass.

	-- Wire all LEDs.
	LED1_SO <= LogicRunSync_S;
	LED2_SO <= LogicUSBFifo_O.ReadSide.Empty_S;
	LED3_SO <= LogicUSBFifo_O.WriteSide.Full_S;

	-- Only run data producers if the whole logic also is running.
	DVSRun_S		<= DVSRunSync_S and LogicRunSync_S;
	APSRun_S		<= APSRunSync_S and LogicRunSync_S;
	IMURun_S		<= IMURunSync_S and LogicRunSync_S;
	ExtTriggerRun_S <= LogicRunSync_S;

	-- Keep data transmission FIFOs in reset if logic is not running, so
	-- that they will be empty when resuming operation (no stale data).
	DVSFifoReset_R		  <= LogicReset_R or (not LogicRunSync_S);
	APSFifoReset_R		  <= LogicReset_R or (not LogicRunSync_S);
	IMUFifoReset_R		  <= LogicReset_R or (not LogicRunSync_S);
	ExtTriggerFifoReset_R <= LogicReset_R or (not LogicRunSync_S);

	-- Generate logic clock using a PLL.
	logicClockPLL : PLL
		generic map (
			CLOCK_FREQ	   => USB_CLOCK_FREQ,
			OUT_CLOCK_FREQ => LOGIC_CLOCK_FREQ)
		port map (
			Clock_CI	=> USBClock_CI,
			Reset_RI	=> USBReset_R,
			OutClock_CO => LogicClock_C);

	usbFX2SM : FX2Statemachine
		port map (
			Clock_CI				=> USBClock_CI,
			Reset_RI				=> USBReset_R,
			USBFifoEP6Full_SI		=> USBFifoFullFlagSync_S,
			USBFifoEP6AlmostFull_SI => USBFifoProgrammableFlagSync_S,
			USBFifoWrite_SBO		=> USBFifoWrite_SBO,
			USBFifoPktEnd_SBO		=> USBFifoPktEnd_SBO,
			InFifo_I				=> LogicUSBFifo_O.ReadSide,
			InFifo_O				=> LogicUSBFifo_I.ReadSide);

	-- Instantiate one FIFO to hold all the events coming out of the mixer-producer state machine.
	logicUSBFifo : FIFODualClock
		generic map (
			DATA_WIDTH		  => USB_FIFO_WIDTH,
			DATA_DEPTH		  => USBLOGIC_FIFO_SIZE,
			EMPTY_FLAG		  => 0,
			ALMOST_EMPTY_FLAG => USBLOGIC_FIFO_ALMOST_EMPTY_SIZE,
			FULL_FLAG		  => USBLOGIC_FIFO_SIZE,
			ALMOST_FULL_FLAG  => USBLOGIC_FIFO_SIZE - USBLOGIC_FIFO_ALMOST_FULL_SIZE)
		port map (
			Reset_RI   => USBReset_R,
			WrClock_CI => LogicClock_C,
			RdClock_CI => USBClock_CI,
			Fifo_I	   => LogicUSBFifo_I,
			Fifo_O	   => LogicUSBFifo_O);

	multiplexerSM : MultiplexerStateMachine
		port map (
			Clock_CI		  => LogicClock_C,
			Reset_RI		  => LogicReset_R,
			Run_SI			  => LogicRunSync_S,
			TimestampReset_SI => '0',
			OutFifo_I		  => LogicUSBFifo_O.WriteSide,
			OutFifo_O		  => LogicUSBFifo_I.WriteSide,
			DVSAERFifo_I	  => DVSAERFifo_O.ReadSide,
			DVSAERFifo_O	  => DVSAERFifo_I.ReadSide,
			APSADCFifo_I	  => APSADCFifo_O.ReadSide,
			APSADCFifo_O	  => APSADCFifo_I.ReadSide,
			IMUFifo_I		  => IMUFifo_O.ReadSide,
			IMUFifo_O		  => IMUFifo_I.ReadSide,
			ExtTriggerFifo_I  => ExtTriggerFifo_O.ReadSide,
			ExtTriggerFifo_O  => ExtTriggerFifo_I.ReadSide);

	dvsAerFifo : FIFO
		generic map (
			DATA_WIDTH		  => EVENT_WIDTH,
			DATA_DEPTH		  => DVSAER_FIFO_SIZE,
			EMPTY_FLAG		  => 0,
			ALMOST_EMPTY_FLAG => DVSAER_FIFO_ALMOST_EMPTY_SIZE,
			FULL_FLAG		  => DVSAER_FIFO_SIZE,
			ALMOST_FULL_FLAG  => DVSAER_FIFO_SIZE - DVSAER_FIFO_ALMOST_FULL_SIZE)
		port map (
			Clock_CI => LogicClock_C,
			Reset_RI => DVSFifoReset_R,
			Fifo_I	 => DVSAERFifo_I,
			Fifo_O	 => DVSAERFifo_O);

	dvsAerSM : DVSAERStateMachine
		port map (
			Clock_CI		=> LogicClock_C,
			Reset_RI		=> LogicReset_R,
			DVSRun_SI		=> DVSRun_S,
			OutFifo_I		=> DVSAERFifo_O.WriteSide,
			OutFifo_O		=> DVSAERFifo_I.WriteSide,
			DVSAERData_DI	=> DVSAERData_DI,
			DVSAERReq_SBI	=> DVSAERReqSync_SB,
			DVSAERAck_SBO	=> DVSAERAck_SBO,
			DVSAERReset_SBO => DVSAERReset_SBO);

	apsAdcFifo : FIFO
		generic map (
			DATA_WIDTH		  => EVENT_WIDTH,
			DATA_DEPTH		  => APSADC_FIFO_SIZE,
			EMPTY_FLAG		  => 0,
			ALMOST_EMPTY_FLAG => APSADC_FIFO_ALMOST_EMPTY_SIZE,
			FULL_FLAG		  => APSADC_FIFO_SIZE,
			ALMOST_FULL_FLAG  => APSADC_FIFO_SIZE - APSADC_FIFO_ALMOST_FULL_SIZE)
		port map (
			Clock_CI => LogicClock_C,
			Reset_RI => APSFifoReset_R,
			Fifo_I	 => APSADCFifo_I,
			Fifo_O	 => APSADCFifo_O);

	apsAdcSM : APSADCStateMachine
		port map (
			Clock_CI			   => LogicClock_C,
			Reset_RI			   => LogicReset_R,
			APSRun_SI			   => APSRun_S,
			OutFifo_I			   => APSADCFifo_O.WriteSide,
			OutFifo_O			   => APSADCFifo_I.WriteSide,
			APSChipRowSRClock_SO   => APSChipRowSRClock_SO,
			APSChipRowSRIn_SO	   => APSChipRowSRIn_SO,
			APSChipColSRClock_SO   => APSChipColSRClock_SO,
			APSChipColSRIn_SO	   => APSChipColSRIn_SO,
			APSChipColMode_DO	   => APSChipColMode_DO,
			APSChipTXGate_SO	   => APSChipTXGate_SO,
			APSADCData_DI		   => APSADCData_DI,
			APSADCOverflow_SI	   => APSADCOverflow_SI,
			APSADCClock_CO		   => APSADCClock_CO,
			APSADCOutputEnable_SBO => APSADCOutputEnable_SBO,
			APSADCStandby_SO	   => APSADCStandby_SO);

	imuFifo : FIFO
		generic map (
			DATA_WIDTH		  => EVENT_WIDTH,
			DATA_DEPTH		  => IMU_FIFO_SIZE,
			EMPTY_FLAG		  => 0,
			ALMOST_EMPTY_FLAG => IMU_FIFO_ALMOST_EMPTY_SIZE,
			FULL_FLAG		  => IMU_FIFO_SIZE,
			ALMOST_FULL_FLAG  => IMU_FIFO_SIZE - IMU_FIFO_ALMOST_FULL_SIZE)
		port map (
			Clock_CI => LogicClock_C,
			Reset_RI => IMUFifoReset_R,
			Fifo_I	 => IMUFifo_I,
			Fifo_O	 => IMUFifo_O);

	imuSM : IMUStateMachine
		port map (
			Clock_CI		=> LogicClock_C,
			Reset_RI		=> LogicReset_R,
			IMURun_SI		=> IMURun_S,
			OutFifo_I		=> IMUFifo_O.WriteSide,
			OutFifo_O		=> IMUFifo_I.WriteSide,
			IMUClock_ZO		=> IMUClock_ZO,
			IMUData_ZIO		=> IMUData_ZIO,
			IMUInterrupt_SI => IMUInterruptSync_S);

	extTriggerFifo : FIFO
		generic map (
			DATA_WIDTH		  => EVENT_WIDTH,
			DATA_DEPTH		  => EXT_TRIGGER_FIFO_SIZE,
			EMPTY_FLAG		  => 0,
			ALMOST_EMPTY_FLAG => EXT_TRIGGER_FIFO_ALMOST_EMPTY_SIZE,
			FULL_FLAG		  => EXT_TRIGGER_FIFO_SIZE,
			ALMOST_FULL_FLAG  => EXT_TRIGGER_FIFO_SIZE - EXT_TRIGGER_FIFO_ALMOST_FULL_SIZE)
		port map (
			Clock_CI => LogicClock_C,
			Reset_RI => ExtTriggerFifoReset_R,
			Fifo_I	 => ExtTriggerFifo_I,
			Fifo_O	 => ExtTriggerFifo_O);

	extTriggerSM : ExtTriggerStateMachine
		port map (
			Clock_CI			=> LogicClock_C,
			Reset_RI			=> LogicReset_R,
			ExtTriggerRun_SI	=> ExtTriggerRun_S,
			OutFifo_I			=> ExtTriggerFifo_O.WriteSide,
			OutFifo_O			=> ExtTriggerFifo_I.WriteSide,
			ExtTriggerSwitch_SI => SyncInSwitchSync_S,
			ExtTriggerSignal_SI => SyncInSignalSync_S);
end Structural;
