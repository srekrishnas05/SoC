library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ============================================================
-- Systolic Array Package
-- ============================================================
-- Shared constants and types for the 32x32 output-stationary
-- INT8 systolic matrix multiplier.
--
--   SIZE       : array dimension (rows = cols = 32)
--   DATA_WIDTH : operand width (signed INT8)
--   ACC_WIDTH  : per-PE accumulator width
--                32 accumulations of 16-bit signed products fit
--                comfortably in 32 bits (worst case ~22 bits).
--
-- Types:
--   data_t      : signed INT8 sample (activation or weight)
--   acc_t       : signed accumulator word
--   data_vec_t  : 1-D vector of INT8 samples (array edges)
--   acc_vec_t   : 1-D vector of accumulator words
--   data_mat_t  : 2-D tile of INT8 samples (operand tiles)
--   acc_mat_t   : 2-D tile of accumulator words (output tile)
-- ============================================================

package systolic_pkg is

    constant SIZE       : natural := 32;
    constant DATA_WIDTH : natural := 8;
    constant ACC_WIDTH  : natural := 32;

    subtype data_t is signed(DATA_WIDTH - 1 downto 0);
    subtype acc_t  is signed(ACC_WIDTH  - 1 downto 0);

    type data_vec_t is array (natural range <>) of data_t;
    type acc_vec_t  is array (natural range <>) of acc_t;
    type data_mat_t is array (natural range <>, natural range <>) of data_t;
    type acc_mat_t  is array (natural range <>, natural range <>) of acc_t;

    -- Ceiling log2, used for address widths in companion buffers
    function clog2(n : positive) return natural;

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

end package body systolic_pkg;