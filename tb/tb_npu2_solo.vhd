library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library work;
use work.systolic_pkg.all;

-- ============================================================
-- Standalone 16x16 NPU correctness testbench
-- ============================================================
-- Tests accelerator_top with SIZE=16 directly.
-- Three cases:
--   Case 1: K=16 (exact fit, no padding needed)
--   Case 2: K=8  (K < SIZE, padding required)
--   Case 3: K=16, identity-style matrices
--
-- All expected values computed locally.
-- ============================================================

entity tb_npu2_solo is
end tb_npu2_solo;

architecture Behavioral of tb_npu2_solo is

    constant SZ : natural := 16;

    signal clk   : std_logic := '0';
    signal rst   : std_logic := '1';
    signal start : std_logic := '0';
    signal done  : std_logic;

    signal a_tile : data_mat_t(0 to SZ-1, 0 to SZ-1) :=
                        (others=>(others=>(others=>'0')));
    signal b_tile : data_mat_t(0 to SZ-1, 0 to SZ-1) :=
                        (others=>(others=>(others=>'0')));
    signal c_tile : acc_mat_t(0 to SZ-1, 0 to SZ-1);

    procedure cpu_tick(signal clk : std_logic) is
    begin
        wait until rising_edge(clk);
    end procedure;

begin

    clk <= not clk after 5 ns;

    dut : entity work.accelerator_top
        generic map (SIZE => SZ)
        port map (clk=>clk, rst=>rst, start=>start,
            a_tile=>a_tile, b_tile=>b_tile,
            c_tile=>c_tile, done=>done);

    process
        variable expected : integer;
        variable got      : integer;
        variable pass     : boolean;
        variable all_pass : boolean := true;

        -- Fire start and wait for done
        procedure run_tile is
        begin
            rst <= '1'; wait for 30 ns;
            rst <= '0'; wait for 10 ns;
            start <= '1'; wait for 10 ns;
            start <= '0';
            wait until done = '1';
            wait for 10 ns;
        end procedure;

        -- Check all SZ x SZ outputs against expected function
        -- exp_fn: expected value at (r,c)
        procedure check(test_name : string;
                        exp_arr : acc_mat_t(0 to SZ-1, 0 to SZ-1)) is
        begin
            pass := true;
            for r in 0 to SZ-1 loop
                for c in 0 to SZ-1 loop
                    expected := to_integer(exp_arr(r,c));
                    got      := to_integer(c_tile(r,c));
                    if expected /= got then
                        report "FAIL " & test_name &
                               " C[" & integer'image(r) & "][" &
                               integer'image(c) & "] expected=" &
                               integer'image(expected) & " got=" &
                               integer'image(got) severity error;
                        pass := false;
                        all_pass := false;
                    end if;
                end loop;
            end loop;
            if pass then
                report "PASS: " & test_name severity note;
            end if;
        end procedure;

        variable ref : acc_mat_t(0 to SZ-1, 0 to SZ-1);
        variable acc : integer;

    begin

        -- --------------------------------------------------------
        -- Case 1: K=16, A[r][k] = 1, B[k][c] = 1
        -- Expected: C[r][c] = 16 for all r,c
        -- --------------------------------------------------------
        for r in 0 to SZ-1 loop
            for k in 0 to SZ-1 loop
                a_tile(r,k) <= to_signed(1, DATA_WIDTH);
            end loop;
        end loop;
        for k in 0 to SZ-1 loop
            for c in 0 to SZ-1 loop
                b_tile(k,c) <= to_signed(1, DATA_WIDTH);
            end loop;
        end loop;
        wait for 1 ns;

        run_tile;

        for r in 0 to SZ-1 loop
            for c in 0 to SZ-1 loop
                ref(r,c) := to_signed(16, ACC_WIDTH);
            end loop;
        end loop;
        check("Case1 K=16 all-ones", ref);

        -- --------------------------------------------------------
        -- Case 2: K=8 (padded), A[r][k]=r+1 for k<8 else 0
        --                        B[k][c]=c+1 for k<8 else 0
        -- Expected: C[r][c] = (r+1)*(c+1) * sum_k=0..7(1) = 8*(r+1)*(c+1)
        -- --------------------------------------------------------
        for r in 0 to SZ-1 loop
            for k in 0 to SZ-1 loop
                if k < 8 then
                    a_tile(r,k) <= to_signed(r+1, DATA_WIDTH);
                else
                    a_tile(r,k) <= to_signed(0, DATA_WIDTH);
                end if;
            end loop;
        end loop;
        for k in 0 to SZ-1 loop
            for c in 0 to SZ-1 loop
                if k < 8 then
                    b_tile(k,c) <= to_signed(c+1, DATA_WIDTH);
                else
                    b_tile(k,c) <= to_signed(0, DATA_WIDTH);
                end if;
            end loop;
        end loop;
        wait for 1 ns;

        run_tile;

        for r in 0 to SZ-1 loop
            for c in 0 to SZ-1 loop
                ref(r,c) := to_signed(8*(r+1)*(c+1), ACC_WIDTH);
            end loop;
        end loop;
        check("Case2 K=8 padded", ref);

        -- --------------------------------------------------------
        -- Case 3: K=16, diagonal A, identity B
        -- A[r][k] = 1 if r=k else 0  (identity-like)
        -- B[k][c] = k+1 (row k filled with k+1)
        -- Expected: C[r][c] = B[r][c] = r+1
        -- --------------------------------------------------------
        for r in 0 to SZ-1 loop
            for k in 0 to SZ-1 loop
                if r = k then
                    a_tile(r,k) <= to_signed(1, DATA_WIDTH);
                else
                    a_tile(r,k) <= to_signed(0, DATA_WIDTH);
                end if;
            end loop;
        end loop;
        for k in 0 to SZ-1 loop
            for c in 0 to SZ-1 loop
                b_tile(k,c) <= to_signed(k+1, DATA_WIDTH);
            end loop;
        end loop;
        wait for 1 ns;

        run_tile;

        for r in 0 to SZ-1 loop
            for c in 0 to SZ-1 loop
                ref(r,c) := to_signed(r+1, ACC_WIDTH);
            end loop;
        end loop;
        check("Case3 identity A", ref);

        -- --------------------------------------------------------
        -- Summary
        -- --------------------------------------------------------
        if all_pass then
            report "=== ALL CASES PASS ===" severity note;
        else
            report "=== SOME CASES FAILED ===" severity failure;
        end if;
        wait;
    end process;

end Behavioral;