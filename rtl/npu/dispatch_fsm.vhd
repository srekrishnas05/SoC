library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.systolic_pkg.all;



entity dispatch_fsm is
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        plan_done  : in  std_logic;
        num_tiles  : in  std_logic_vector(15 downto 0);
        sched_re   : out std_logic;
        sched_addr : out std_logic_vector(15 downto 0);
        sched_data : in  std_logic_vector(DESC_WIDTH - 1 downto 0);
        cmd_wr_en  : out std_logic_vector(NUM_NPUS - 1 downto 0);
        cmd_data   : out std_logic_vector(DESC_WIDTH - 1 downto 0);
        cmd_full   : in  std_logic_vector(NUM_NPUS - 1 downto 0);
        done_sync  : in  std_logic_vector(NUM_NPUS - 1 downto 0);
        job_done   : out std_logic
    );
end dispatch_fsm;

architecture Behavioral of dispatch_fsm is

    type dispatch_state_t is (D_IDLE, D_FETCH, D_DECODE, D_ISSUE, D_WAIT);
    signal state_r      : dispatch_state_t   := D_IDLE;
    signal sched_idx_r  : unsigned(15 downto 0) := (others => '0');
    signal num_tiles_r  : unsigned(15 downto 0) := (others => '0');
    signal desc_r       : std_logic_vector(DESC_WIDTH - 1 downto 0) := (others => '0');
    signal target_npu_r : natural range 0 to NUM_NPUS - 1 := 0;
    signal tiles_done_r : unsigned(15 downto 0) := (others => '0');

begin

    process(clk)
        variable npu_id_v    : natural range 0 to NUM_NPUS - 1;
        variable done_inc_v  : unsigned(15 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state_r      <= D_IDLE;
                sched_idx_r  <= (others => '0');
                num_tiles_r  <= (others => '0');
                tiles_done_r <= (others => '0');
                sched_re     <= '0';
                cmd_wr_en    <= (others => '0');
                cmd_data     <= (others => '0');
                job_done     <= '0';
                desc_r       <= (others => '0');
                target_npu_r <= 0;
            else
                sched_re  <= '0';
                cmd_wr_en <= (others => '0');
                job_done  <= '0';

                done_inc_v := (others => '0');
                for i in 0 to NUM_NPUS - 1 loop
                    if done_sync(i) = '1' then
                        done_inc_v := done_inc_v + 1;
                    end if;
                end loop;
                tiles_done_r <= tiles_done_r + done_inc_v;

                case state_r is

                    -- 
                    when D_IDLE =>
                        sched_idx_r <= (others => '0');
                        if plan_done = '1' then
                            num_tiles_r  <= unsigned(num_tiles);
                            tiles_done_r <= done_inc_v; -- reset + any concurrent done
                            state_r      <= D_FETCH;
                        end if;

                    
                    when D_FETCH =>
                        sched_re   <= '1';
                        sched_addr <= std_logic_vector(sched_idx_r);
                        state_r    <= D_DECODE;

                    when D_DECODE =>
                        desc_r       <= sched_data;
                        target_npu_r <= to_integer(
                            unsigned(sched_data(135 downto 133)));
                        state_r      <= D_ISSUE;

                    when D_ISSUE =>
                        npu_id_v := target_npu_r;
                        if cmd_full(npu_id_v) = '0' then
                            cmd_wr_en(npu_id_v) <= '1';
                            cmd_data            <= desc_r;
                            sched_idx_r         <= sched_idx_r + 1;
                            if sched_idx_r = num_tiles_r - 1 then
                                state_r <= D_WAIT;
                            else
                                state_r <= D_FETCH;
                            end if;
                        end if;

                    when D_WAIT =>
                        if (tiles_done_r + done_inc_v) = num_tiles_r then
                            job_done <= '1';
                            state_r  <= D_IDLE;
                        end if;

                end case;
            end if;
        end if;
    end process;

end Behavioral;