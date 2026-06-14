library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;



package systolic_pkg is

    constant DATA_WIDTH : natural := 8;
    constant ACC_WIDTH  : natural := 32;

    -- Number of NPU instances in the cluster
    constant NUM_NPUS   : natural := 6;

    -- Serialized tile descriptor width (bits)
    -- Layout: a_addr(32) + b_addr(32) + c_addr(32) + tile_row(8)
    --       + tile_col(8) + k_slice(8) + pad_rows(6) + pad_cols(6)
    --       + is_last_k(1) + npu_id(3) = 136 bits
    constant DESC_WIDTH : natural := 136;

    -- NPU size table (indexed by NPU_ID)
    -- Used by tile_planner to know each array's dimension
    type npu_size_table_t is array (0 to NUM_NPUS - 1) of natural;
    constant NPU_SIZES : npu_size_table_t := (64, 32, 16, 8, 4, 4);

    subtype data_t is signed(DATA_WIDTH - 1 downto 0);
    subtype acc_t  is signed(ACC_WIDTH  - 1 downto 0);

    type data_vec_t is array (natural range <>) of data_t;
    type acc_vec_t  is array (natural range <>) of acc_t;
    type data_mat_t is array (natural range <>, natural range <>) of data_t;
    type acc_mat_t  is array (natural range <>, natural range <>) of acc_t;

    -- Tile descriptor passed from dispatcher to each NPU via async FIFO.
    -- All address fields are byte addresses into the shared tile SRAM.
    type tile_desc_t is record
        tile_row   : natural;   -- output tile row index
        tile_col   : natural;   -- output tile col index
        k_slice    : natural;   -- K-dimension partition index
        a_addr     : std_logic_vector(31 downto 0);
        b_addr     : std_logic_vector(31 downto 0);
        c_addr     : std_logic_vector(31 downto 0);
        is_last_k  : std_logic; -- '1' = write final result, not partial sum
        pad_rows   : natural range 0 to 63;  -- zero-padding on bottom edge
        pad_cols   : natural range 0 to 63;  -- zero-padding on right edge
    end record;

    -- Ceiling log2, used for address widths
    function clog2(n : positive) return natural;

    -- Ceiling division
    function ceil_div(a : natural; b : positive) return natural;

end package systolic_pkg;

package body systolic_pkg is

    function clog2(n : positive) return natural is
        variable value_v : natural := n - 1;
        variable ret_v   : natural := 0;
    begin
        while value_v > 0 loop
            value_v := value_v / 2;
            ret_v   := ret_v + 1;
        end loop;
        return ret_v;
    end function;

    function ceil_div(a : natural; b : positive) return natural is
    begin
        return (a + b - 1) / b;
    end function;

end package body systolic_pkg;