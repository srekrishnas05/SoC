library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.systolic_pkg.all;

-- ============================================================
-- NPU Controller FSM
-- ============================================================
-- Sequences one matrix-multiply over the 32x32 array:
--
--   IDLE     : wait for start
--   COMPUTE  : SIZE cycles, stream operands into the array
--              and pulse acc_clr on the very first cycle
--   DRAIN    : (2*SIZE - 1) cycles, let the last operands
--              propagate diagonally through the array
--   STORE    : SIZE cycles, latch the output tile,
--              assert done on the final cycle
--
-- Outputs are derived combinationally from state_r/cnt_r so
-- they line up cycle-by-cycle with the datapath registers.
-- ============================================================

entity controller_fsm is
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        start      : in  std_logic;
        acc_clr    : out std_logic;
        stream_en  : out std_logic;
        pe_en      : out std_logic;
        store      : out std_logic;
        swap       : out std_logic;
        done       : out std_logic;
        stream_idx : out natural range 0 to SIZE - 1
    );
end controller_fsm;

architecture Behavioral of controller_fsm is

    type state_t is (S_IDLE, S_COMPUTE, S_DRAIN, S_STORE);

    signal state_r : state_t := S_IDLE;
    signal cnt_r   : natural range 0 to (2 * SIZE - 1) := 0;

    constant DRAIN_LAST : natural := 2 * SIZE - 2;

begin

    -- --------------------------------------------------------
    -- State / counter update (single-process FSM)
    -- --------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state_r <= S_IDLE;
                cnt_r   <= 0;
            else
            case state_r is
                when S_IDLE =>
                    cnt_r <= 0;
                    if start = '1' then
                        state_r <= S_COMPUTE;
                        cnt_r   <= 0;
                    end if;

                when S_COMPUTE =>
                    if cnt_r = SIZE - 1 then
                        state_r <= S_DRAIN;
                        cnt_r   <= 0;
                    else
                        cnt_r <= cnt_r + 1;
                    end if;

                when S_DRAIN =>
                    if cnt_r = DRAIN_LAST then
                        state_r <= S_STORE;
                        cnt_r   <= 0;
                    else
                        cnt_r <= cnt_r + 1;
                    end if;

                when S_STORE =>
                    if cnt_r = SIZE - 1 then
                        state_r <= S_IDLE;
                        cnt_r   <= 0;
                    else
                        cnt_r <= cnt_r + 1;
                    end if;
            end case;
            end if;
        end if;
    end process;

    -- --------------------------------------------------------
    -- Output decode (combinational)
    -- --------------------------------------------------------
    process(all)
    begin
        acc_clr    <= '0';
        stream_en  <= '0';
        pe_en      <= '0';
        store      <= '0';
        swap       <= '0';
        done       <= '0';
        stream_idx <= 0;

        case state_r is
            when S_IDLE =>
                null;

            when S_COMPUTE =>
                stream_en  <= '1';
                pe_en      <= '1';
                stream_idx <= cnt_r;
                if cnt_r = 0 then
                    acc_clr <= '1';
                end if;

            when S_DRAIN =>
                pe_en <= '1';

            when S_STORE =>
                store <= '1';
                if cnt_r = SIZE - 1 then
                    swap <= '1';
                    done <= '1';
                end if;
        end case;
    end process;

end Behavioral;