library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.systolic_pkg.all;



entity controller_fsm is
    generic (
        SIZE : natural := 32
    );
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

    signal state_r : state_t               := S_IDLE;
    signal cnt_r   : natural range 0 to (2 * SIZE - 1) := 0;

    constant DRAIN_LAST : natural := 2 * SIZE - 2;

begin

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

s    acc_clr    <= '1' when (state_r = S_IDLE and start = '1') else '0';
    stream_en  <= '1' when  state_r = S_COMPUTE               else '0';
    pe_en      <= '1' when (state_r = S_COMPUTE or
                            state_r = S_DRAIN)                 else '0';
    store      <= '1' when  state_r = S_STORE                  else '0';
    swap       <= '1' when (state_r = S_STORE and cnt_r = SIZE - 1) else '0';
    done       <= '1' when (state_r = S_STORE and cnt_r = SIZE - 1) else '0';
    stream_idx <= cnt_r when cnt_r < SIZE else 0;

end Behavioral;