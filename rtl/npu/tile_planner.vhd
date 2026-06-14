library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.systolic_pkg.all;



entity tile_planner is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;

        -- Job descriptor (written by CPU before job_start)
        job_start : in  std_logic;
        job_m     : in  std_logic_vector(15 downto 0);  -- rows of A / rows of C
        job_k     : in  std_logic_vector(15 downto 0);  -- cols of A / rows of B
        job_n     : in  std_logic_vector(15 downto 0);  -- cols of B / cols of C
        job_a_base: in  std_logic_vector(31 downto 0);
        job_b_base: in  std_logic_vector(31 downto 0);
        job_c_base: in  std_logic_vector(31 downto 0);

        -- Schedule RAM write port
        sched_we   : out std_logic;
        sched_addr : out std_logic_vector(15 downto 0);  -- up to 65536 entries
        sched_data : out std_logic_vector(135 downto 0); -- serialized tile_desc_t

        -- Status
        plan_done  : out std_logic;
        num_tiles  : out std_logic_vector(15 downto 0)
    );
end tile_planner;

architecture Behavioral of tile_planner is

    type plan_state_t is (
        P_IDLE,
        P_SETUP,    -- compute derived dimensions (1 cycle)
        P_INT,      -- interior 64x64 blocks
        P_REDGE,    -- right edge strip
        P_BEDGE,    -- bottom edge strip
        P_CORN,     -- bottom-right corner
        P_DONE
    );
    signal state_r : plan_state_t := P_IDLE;

    signal m_r       : natural := 0;
    signal k_r       : natural := 0;
    signal n_r       : natural := 0;
    signal a_base_r  : unsigned(31 downto 0) := (others => '0');
    signal b_base_r  : unsigned(31 downto 0) := (others => '0');
    signal c_base_r  : unsigned(31 downto 0) := (others => '0');

    signal int_rows_r  : natural := 0;  -- floor(M/64)
    signal int_cols_r  : natural := 0;  -- floor(N/64)
    signal rem_m_r     : natural := 0;  -- M mod 64
    signal rem_n_r     : natural := 0;  -- N mod 64

    -- NPU assignment for each region
    signal redge_npu_r : natural range 0 to NUM_NPUS - 1 := 5;
    signal bedge_npu_r : natural range 0 to NUM_NPUS - 1 := 5;
    signal corn_npu_r  : natural range 0 to NUM_NPUS - 1 := 5;

    signal tr_r     : natural := 0;  -- tile row index
    signal tc_r     : natural := 0;  -- tile col index
    signal ks_r     : natural := 0;  -- k-slice index
    signal npu_r    : natural range 0 to NUM_NPUS - 1 := 0;  -- assigned NPU
    signal t_size_r : natural := 64; -- tile size for current region

    -- Schedule write counter
    signal sched_cnt_r : natural := 0;

    function select_npu(dim : natural) return natural is
    begin
        if    dim >= 64 then return 0;  -- 64x64
        elsif dim >= 32 then return 1;  -- 32x32
        elsif dim >= 16 then return 2;  -- 16x16
        elsif dim >= 8  then return 3;  -- 8x8
        else                 return 4;  -- 4x4 (instance A; B used for corner split later)
        end if;
    end function;

    function num_k_slices(k : natural; t : natural) return natural is
    begin
        return (k + t - 1) / t;
    end function;

    function pack_desc(
        a_addr   : unsigned(31 downto 0);
        b_addr   : unsigned(31 downto 0);
        c_addr   : unsigned(31 downto 0);
        tile_row : natural;
        tile_col : natural;
        k_slice  : natural;
        pad_rows : natural;
        pad_cols : natural;
        is_last_k: std_logic;
        npu_id   : natural range 0 to NUM_NPUS - 1
    ) return std_logic_vector is
        variable d : std_logic_vector(135 downto 0) := (others => '0');
    begin
        d(31  downto 0)   := std_logic_vector(a_addr);
        d(63  downto 32)  := std_logic_vector(b_addr);
        d(95  downto 64)  := std_logic_vector(c_addr);
        d(103 downto 96)  := std_logic_vector(to_unsigned(tile_row, 8));
        d(111 downto 104) := std_logic_vector(to_unsigned(tile_col, 8));
        d(119 downto 112) := std_logic_vector(to_unsigned(k_slice,  8));
        d(125 downto 120) := std_logic_vector(to_unsigned(pad_rows, 6));
        d(131 downto 126) := std_logic_vector(to_unsigned(pad_cols, 6));
        d(132)            := is_last_k;
        d(135 downto 133) := std_logic_vector(to_unsigned(npu_id,   3));
        return d;
    end function;

    function calc_a_addr(
        base     : unsigned(31 downto 0);
        tile_row : natural;
        k_slice  : natural;
        t        : natural;
        k        : natural
    ) return unsigned is
    begin
        return base + to_unsigned((tile_row * t * k) + (k_slice * t), 32);
    end function;

    function calc_b_addr(
        base     : unsigned(31 downto 0);
        k_slice  : natural;
        tile_col : natural;
        t        : natural;
        n        : natural
    ) return unsigned is
    begin
        return base + to_unsigned((k_slice * t * n) + (tile_col * t), 32);
    end function;

    function calc_c_addr(
        base     : unsigned(31 downto 0);
        tile_row : natural;
        tile_col : natural;
        t        : natural;
        n        : natural
    ) return unsigned is
    begin
        return base + to_unsigned(4 * ((tile_row * t * n) + (tile_col * t)), 32);
    end function;

begin

    process(clk)
        variable t        : natural;
        variable nk       : natural;
        variable pad_r    : natural;
        variable pad_c    : natural;
        variable is_last  : std_logic;
        variable a_addr_v : unsigned(31 downto 0);
        variable b_addr_v : unsigned(31 downto 0);
        variable c_addr_v : unsigned(31 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state_r    <= P_IDLE;
                sched_we   <= '0';
                plan_done  <= '0';
                sched_cnt_r <= 0;

            else
                -- Default outputs
                sched_we  <= '0';
                plan_done <= '0';

                case state_r is

                    when P_IDLE =>
                        sched_cnt_r <= 0;
                        if job_start = '1' then
                            -- Latch job descriptor
                            m_r      <= to_integer(unsigned(job_m));
                            k_r      <= to_integer(unsigned(job_k));
                            n_r      <= to_integer(unsigned(job_n));
                            a_base_r <= unsigned(job_a_base);
                            b_base_r <= unsigned(job_b_base);
                            c_base_r <= unsigned(job_c_base);
                            state_r  <= P_SETUP;
                        end if;

                    when P_SETUP =>
                        -- Compute derived quantities (1 cycle)
                        int_rows_r <= m_r / 64;
                        int_cols_r <= n_r / 64;
                        rem_m_r    <= m_r mod 64;
                        rem_n_r    <= n_r mod 64;

                        redge_npu_r <= 0;  -- always 64x64
                        bedge_npu_r <= 0;  -- always 64x64

                        -- Corner NPU: tile is (rem_m x rem_n).
                        -- Assign largest NPU that fits both dimensions.
                        if (m_r mod 64) > (n_r mod 64) then
                            corn_npu_r <= select_npu(m_r mod 64);
                        else
                            corn_npu_r <= select_npu(n_r mod 64);
                        end if;

                        -- Initialize loop counters for Pass 1
                        tr_r     <= 0;
                        tc_r     <= 0;
                        ks_r     <= 0;
                        npu_r    <= 0;      -- 64x64
                        t_size_r <= 64;

                        if m_r / 64 > 0 and n_r / 64 > 0 then
                            state_r <= P_INT;
                        elsif n_r mod 64 > 0 then
                            state_r  <= P_REDGE;
                            npu_r    <= 0;   -- 64x64
                            t_size_r <= 64;
                            tr_r     <= 0; tc_r <= 0; ks_r <= 0;
                        elsif m_r mod 64 > 0 then
                            state_r  <= P_BEDGE;
                            npu_r    <= 0;   -- 64x64
                            t_size_r <= 64;
                            tr_r     <= 0; tc_r <= 0; ks_r <= 0;
                        else
                            state_r <= P_DONE;
                        end if;

                    when P_INT =>
                        t  := 64;
                        nk := num_k_slices(k_r, t);

                        if ks_r = nk - 1 then
                            is_last := '1';
                        else
                            is_last := '0';
                        end if;

                        -- No padding in interior tiles
                        pad_r := 0;
                        pad_c := 0;

                        a_addr_v := calc_a_addr(a_base_r, tr_r, ks_r, t, k_r);
                        b_addr_v := calc_b_addr(b_base_r, ks_r, tc_r, t, n_r);
                        c_addr_v := calc_c_addr(c_base_r, tr_r, tc_r, t, n_r);

                        sched_we   <= '1';
                        sched_addr <= std_logic_vector(to_unsigned(sched_cnt_r, 16));
                        sched_data <= pack_desc(
                            a_addr_v, b_addr_v, c_addr_v,
                            tr_r, tc_r, ks_r,
                            pad_r, pad_c, is_last, 0);  -- npu_id=0 (64x64)

                        sched_cnt_r <= sched_cnt_r + 1;

                        -- Advance counters: ks -> tc -> tr
                        if ks_r < nk - 1 then
                            ks_r <= ks_r + 1;
                        else
                            ks_r <= 0;
                            if tc_r < int_cols_r - 1 then
                                tc_r <= tc_r + 1;
                            else
                                tc_r <= 0;
                                if tr_r < int_rows_r - 1 then
                                    tr_r <= tr_r + 1;
                                else
                                    -- Interior done, move to right edge
                                    tr_r <= 0; tc_r <= 0; ks_r <= 0;
                                    if rem_n_r > 0 then
                                        state_r  <= P_REDGE;
                                        npu_r    <= 0;   -- 64x64
                                        t_size_r <= 64;
                                    elsif rem_m_r > 0 then
                                        state_r  <= P_BEDGE;
                                        npu_r    <= 0;   -- 64x64
                                        t_size_r <= 64;
                                    else
                                        state_r <= P_DONE;
                                    end if;
                                end if;
                            end if;
                        end if;

                    when P_REDGE =>
                        t  := t_size_r;
                        nk := num_k_slices(k_r, t);

                        if ks_r = nk - 1 then
                            is_last := '1';
                        else
                            is_last := '0';
                        end if;

                        pad_r := 0;
                        pad_c := t - rem_n_r;  -- pad right edge to NPU width

                        -- Right edge tiles: tile_col = int_cols_r (one past interior)
                        a_addr_v := calc_a_addr(a_base_r, tr_r, ks_r, t, k_r);
                        b_addr_v := calc_b_addr(b_base_r, ks_r, int_cols_r, t, n_r);
                        c_addr_v := calc_c_addr(c_base_r, tr_r, int_cols_r, t, n_r);

                        sched_we   <= '1';
                        sched_addr <= std_logic_vector(to_unsigned(sched_cnt_r, 16));
                        sched_data <= pack_desc(
                            a_addr_v, b_addr_v, c_addr_v,
                            tr_r, int_cols_r, ks_r,
                            pad_r, pad_c, is_last, redge_npu_r);

                        sched_cnt_r <= sched_cnt_r + 1;

                        if ks_r < nk - 1 then
                            ks_r <= ks_r + 1;
                        else
                            ks_r <= 0;
                            if tr_r < int_rows_r - 1 then
                                tr_r <= tr_r + 1;
                            else
                                -- Right edge done
                                tr_r <= 0; tc_r <= 0; ks_r <= 0;
                                if rem_m_r > 0 then
                                    state_r  <= P_BEDGE;
                                    npu_r    <= 0;   -- 64x64
                                    t_size_r <= 64;
                                else
                                    state_r <= P_DONE;
                                end if;
                            end if;
                        end if;

                    when P_BEDGE =>
                        t  := t_size_r;
                        nk := num_k_slices(k_r, t);

                        if ks_r = nk - 1 then
                            is_last := '1';
                        else
                            is_last := '0';
                        end if;

                        pad_r := t - rem_m_r;  -- pad bottom edge to NPU height
                        pad_c := 0;

                        a_addr_v := calc_a_addr(a_base_r, int_rows_r, ks_r, t, k_r);
                        b_addr_v := calc_b_addr(b_base_r, ks_r, tc_r, t, n_r);
                        c_addr_v := calc_c_addr(c_base_r, int_rows_r, tc_r, t, n_r);

                        sched_we   <= '1';
                        sched_addr <= std_logic_vector(to_unsigned(sched_cnt_r, 16));
                        sched_data <= pack_desc(
                            a_addr_v, b_addr_v, c_addr_v,
                            int_rows_r, tc_r, ks_r,
                            pad_r, pad_c, is_last, bedge_npu_r);

                        sched_cnt_r <= sched_cnt_r + 1;

                        if ks_r < nk - 1 then
                            ks_r <= ks_r + 1;
                        else
                            ks_r <= 0;
                            if tc_r < int_cols_r - 1 then
                                tc_r <= tc_r + 1;
                            else
                                -- Bottom edge done
                                tr_r <= 0; tc_r <= 0; ks_r <= 0;
                                if rem_m_r > 0 and rem_n_r > 0 then
                                    state_r  <= P_CORN;
                                    npu_r    <= corn_npu_r;
                                    t_size_r <= NPU_SIZES(corn_npu_r);
                                else
                                    state_r <= P_DONE;
                                end if;
                            end if;
                        end if;

                    when P_CORN =>
                        t  := t_size_r;
                        nk := num_k_slices(k_r, t);

                        if ks_r = nk - 1 then
                            is_last := '1';
                        else
                            is_last := '0';
                        end if;

                        pad_r := t - rem_m_r;
                        pad_c := t - rem_n_r;

                        a_addr_v := calc_a_addr(a_base_r, int_rows_r, ks_r, t, k_r);
                        b_addr_v := calc_b_addr(b_base_r, ks_r, int_cols_r, t, n_r);
                        c_addr_v := calc_c_addr(c_base_r, int_rows_r, int_cols_r, t, n_r);

                        sched_we   <= '1';
                        sched_addr <= std_logic_vector(to_unsigned(sched_cnt_r, 16));
                        sched_data <= pack_desc(
                            a_addr_v, b_addr_v, c_addr_v,
                            int_rows_r, int_cols_r, ks_r,
                            pad_r, pad_c, is_last, corn_npu_r);

                        sched_cnt_r <= sched_cnt_r + 1;

                        if ks_r < nk - 1 then
                            ks_r <= ks_r + 1;
                        else
                            state_r <= P_DONE;
                        end if;

                    when P_DONE =>
                        plan_done <= '1';
                        num_tiles <= std_logic_vector(
                            to_unsigned(sched_cnt_r, 16));
                        state_r   <= P_IDLE;

                end case;
            end if;
        end if;
    end process;

end Behavioral;