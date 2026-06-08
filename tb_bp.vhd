library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ============================================================
-- Testbench: branch_predictor
-- ============================================================
-- KEY TIMING RULE:
--   Branch is at Fetch on cycle N.
--   pred_pipe shifts the prediction F->D->E->M over 3 clock edges.
--   update_en must be asserted at cycle N+3 (branch in M stage).
--   mispredict is combinational: valid immediately when update_en high.
--
-- Clock: 10ns period (rising edge at 5, 15, 25 ... ns)
--
-- Tests:
--  1. Initial state: all counters="10", predict_taken=1 for any PC
--  2. BTB starts at zero before first update
--  3. Correct taken prediction: mispredict=0, counter → "11"
--  4. BTB updates after branch resolves
--  5. Counter saturates at "11" (no overflow)
--  6. Misprediction: predicted taken, actual not-taken → mispredict=1
--  7. Counter decrements after not-taken: "11"→"10"
--  8. Counter saturates at "00" (no underflow)
-- ============================================================

entity tb_branch_predictor is
end tb_branch_predictor;

architecture Behavioral of tb_branch_predictor is

    signal clk            : std_logic := '0';
    signal pc_fetch       : std_logic_vector(31 downto 0) := (others => '0');
    signal predict_taken  : std_logic;
    signal predict_target : std_logic_vector(31 downto 0);
    signal update_en      : std_logic := '0';
    signal update_pc      : std_logic_vector(31 downto 0) := (others => '0');
    signal actual_taken   : std_logic := '0';
    signal actual_target  : std_logic_vector(31 downto 0) := (others => '0');
    signal mispredict     : std_logic;

    component branch_predictor port(
        clk            : in  std_logic;
        pc_fetch       : in  std_logic_vector(31 downto 0);
        predict_taken  : out std_logic;
        predict_target : out std_logic_vector(31 downto 0);
        update_en      : in  std_logic;
        update_pc      : in  std_logic_vector(31 downto 0);
        actual_taken   : in  std_logic;
        actual_target  : in  std_logic_vector(31 downto 0);
        mispredict     : out std_logic);
    end component;

    procedure check(condition : in boolean; name : in string) is
    begin
        if condition then
            report "PASS [" & name & "]" severity note;
        else
            report "FAIL [" & name & "]" severity error;
        end if;
    end procedure;

    -- Simulate one branch through the full F->D->E->M pipeline.
    -- Call this at the start of a clock cycle where the branch is at Fetch.
    -- It advances 3 cycles then asserts update_en for one cycle.
    --
    -- Parameters:
    --   b_pc      : PC of the branch instruction
    --   b_taken   : whether the branch actually took
    --   b_target  : actual branch target address
    procedure do_branch(
        signal clk          : in  std_logic;
        signal pc_fetch_sig : out std_logic_vector(31 downto 0);
        signal update_en_s  : out std_logic;
        signal update_pc_s  : out std_logic_vector(31 downto 0);
        signal actual_tkn   : out std_logic;
        signal actual_tgt   : out std_logic_vector(31 downto 0);
        b_pc     : in std_logic_vector(31 downto 0);
        b_taken  : in std_logic;
        b_target : in std_logic_vector(31 downto 0)) is
    begin
        -- Cycle N: branch at Fetch. Set pc_fetch to branch address.
        pc_fetch_sig <= b_pc;
        update_en_s  <= '0';
        wait until rising_edge(clk);  -- pred_pipe(0) captures prediction

        -- Cycle N+1: branch in D
        wait until rising_edge(clk);  -- pred_pipe(1) captures

        -- Cycle N+2: branch in E
        wait until rising_edge(clk);  -- pred_pipe(2) captures; pred_was now valid

        -- Cycle N+3: branch in M - assert update_en
        update_en_s <= '1';
        update_pc_s <= b_pc;
        actual_tkn  <= b_taken;
        actual_tgt  <= b_target;
        wait for 1 ns;  -- let mispredict settle combinatorially
    end procedure;

begin

    clk <= not clk after 5 ns;

    dut : branch_predictor port map(
        clk            => clk,
        pc_fetch       => pc_fetch,
        predict_taken  => predict_taken,
        predict_target => predict_target,
        update_en      => update_en,
        update_pc      => update_pc,
        actual_taken   => actual_taken,
        actual_target  => actual_target,
        mispredict     => mispredict);

    process
    begin
        -- Let reset state settle
        wait for 2 ns;

        -- --------------------------------------------------------
        -- TEST 1: Initial state - counters all "10" → predict_taken=1
        -- Check several different PCs
        -- --------------------------------------------------------
        pc_fetch <= x"00000000";
        wait for 1 ns;
        check(predict_taken = '1',  "T1a: PC=0x00 initially predicts taken");

        pc_fetch <= x"00000010";
        wait for 1 ns;
        check(predict_taken = '1',  "T1b: PC=0x10 initially predicts taken");

        pc_fetch <= x"000000FC";
        wait for 1 ns;
        check(predict_taken = '1',  "T1c: PC=0xFC initially predicts taken");

        -- --------------------------------------------------------
        -- TEST 2: BTB starts at zero - predict_target=0 before any update
        -- --------------------------------------------------------
        pc_fetch <= x"00000000";
        wait for 1 ns;
        check(predict_target = x"00000000",  "T2: BTB initialized to zero");

        -- --------------------------------------------------------
        -- TEST 3: Correct taken prediction - mispredict must be 0
        -- Branch at PC=0x00000008, actually taken to 0x00000050
        -- Initial counter="10" → predict_taken=1 → prediction correct
        -- --------------------------------------------------------
        pc_fetch   <= x"00000008";
        update_en  <= '0';
        wait for 1 ns;
        check(predict_taken = '1',  "T3: predicts taken before branch runs");

        -- Send branch through pipeline: 3 cycles then update
        wait until rising_edge(clk); -- N: branch at F, pred_pipe(0) <= '1'
        wait until rising_edge(clk); -- N+1: D
        wait until rising_edge(clk); -- N+2: E; pred_was now = '1'
        update_en    <= '1';
        update_pc    <= x"00000008";
        actual_taken <= '1';
        actual_target <= x"00000050";
        wait for 1 ns;
        check(mispredict = '0',  "T3: no mispredict when prediction correct (taken=taken)");

        -- Latch the update
        wait until rising_edge(clk);
        update_en <= '0';
        wait for 1 ns;

        -- --------------------------------------------------------
        -- TEST 4: BTB updated - predict_target should now be 0x00000050
        -- --------------------------------------------------------
        pc_fetch <= x"00000008";
        wait for 1 ns;
        check(predict_target = x"00000050",  "T4: BTB updated to actual target");

        -- --------------------------------------------------------
        -- TEST 5: Counter now "11" (was "10", got one taken update)
        -- One more taken update - should saturate and stay "11"
        -- Prediction should still be taken
        -- --------------------------------------------------------
        check(predict_taken = '1',  "T5a: still predicts taken after update");

        wait until rising_edge(clk); -- N: F
        wait until rising_edge(clk); -- N+1: D
        wait until rising_edge(clk); -- N+2: E
        update_en    <= '1';
        update_pc    <= x"00000008";
        actual_taken <= '1';
        actual_target <= x"00000050";
        wait for 1 ns;
        check(mispredict = '0',  "T5b: no mispredict on second taken (counter saturating)");

        wait until rising_edge(clk);
        update_en <= '0';
        wait for 1 ns;
        -- Counter should now be "11" - still predict taken
        pc_fetch <= x"00000008";
        wait for 1 ns;
        check(predict_taken = '1',  "T5c: predict_taken=1 after saturation at 11");

        -- --------------------------------------------------------
        -- TEST 6: Misprediction - counter="11", predict taken, actual NOT taken
        -- mispredict must assert
        -- --------------------------------------------------------
        -- Counter for PC=0x08 is now "11" → predict_taken=1
        -- Actual: not taken
        wait until rising_edge(clk); -- N: F, pred_pipe(0) <= '1'
        wait until rising_edge(clk); -- N+1: D
        wait until rising_edge(clk); -- N+2: E; pred_was='1'
        update_en    <= '1';
        update_pc    <= x"00000008";
        actual_taken <= '0';   -- NOT taken this time
        actual_target <= x"00000000";
        wait for 1 ns;
        check(mispredict = '1',  "T6: mispredict asserts (predicted taken, actual not-taken)");

        wait until rising_edge(clk);
        update_en <= '0';
        wait for 1 ns;

        -- Counter should now be "10" (decremented from "11")
        -- Still predicts taken (MSB still 1)
        pc_fetch <= x"00000008";
        wait for 1 ns;
        check(predict_taken = '1',  "T6b: still predicts taken after one decrement (counter=10)");

        -- --------------------------------------------------------
        -- TEST 7: Another not-taken - counter "10" → "01"
        -- Now predict_taken should flip to 0
        -- --------------------------------------------------------
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        update_en    <= '1';
        update_pc    <= x"00000008";
        actual_taken <= '0';
        actual_target <= x"00000000";
        wait for 1 ns;
        check(mispredict = '1',  "T7a: mispredict again (predicted taken, actual not-taken, counter=10)");

        wait until rising_edge(clk);
        update_en <= '0';
        wait for 1 ns;

        -- Counter now "01" - predict_taken should be 0
        pc_fetch <= x"00000008";
        wait for 1 ns;
        check(predict_taken = '0',  "T7b: predict_taken flips to 0 when counter reaches 01");

        -- --------------------------------------------------------
        -- TEST 8: Counter saturation at "00"
        -- Two more not-taken updates: "01"→"00"→"00"(saturated)
        -- Use a fresh PC to start from "10" and drive down cleanly
        -- --------------------------------------------------------
        -- Fresh PC: 0x00000020, starts at "10"
        -- Drive to "00": need 2 not-taken updates (10→01→00)
        pc_fetch <= x"00000020";
        wait for 1 ns;
        check(predict_taken = '1',  "T8a: fresh PC starts at weakly taken");

        -- Not-taken 1: "10" → "01"
        wait until rising_edge(clk); wait until rising_edge(clk); wait until rising_edge(clk);
        update_en <= '1'; update_pc <= x"00000020";
        actual_taken <= '0'; actual_target <= x"00000000";
        wait until rising_edge(clk); update_en <= '0'; wait for 1 ns;

        -- Not-taken 2: "01" → "00"
        wait until rising_edge(clk); wait until rising_edge(clk); wait until rising_edge(clk);
        update_en <= '1'; update_pc <= x"00000020";
        actual_taken <= '0'; actual_target <= x"00000000";
        wait until rising_edge(clk); update_en <= '0'; wait for 1 ns;

        pc_fetch <= x"00000020";
        wait for 1 ns;
        check(predict_taken = '0',  "T8b: predict_taken=0 at floor (counter=00)");

        -- Not-taken 3: "00" → should stay "00" (saturated, no underflow)
        wait until rising_edge(clk); wait until rising_edge(clk); wait until rising_edge(clk);
        update_en <= '1'; update_pc <= x"00000020";
        actual_taken <= '0'; actual_target <= x"00000000";
        wait for 1 ns;
        check(mispredict = '0',  "T8c: no mispredict when predicting not-taken correctly");
        wait until rising_edge(clk); update_en <= '0'; wait for 1 ns;

        pc_fetch <= x"00000020";
        wait for 1 ns;
        check(predict_taken = '0',  "T8d: counter stays at 00 (no underflow)");

        -- --------------------------------------------------------
        report "=== Branch predictor testbench complete ===" severity note;
        wait;
    end process;

end Behavioral;