library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity sqrt_pipelined_tb is
end sqrt_pipelined_tb;

architecture tb of sqrt_pipelined_tb is

  constant C_IN_BW      : integer := 16;
  constant C_OUT_BW     : integer := 16;
  constant C_OUT_FRAC   : integer := 8;
  constant C_CLK_PERIOD : time := 10 ns;

  signal clk       : std_logic := '0';
  signal reset     : std_logic := '0';
  signal d_in      : std_logic_vector(C_IN_BW-1 downto 0) := (others => '0');
  signal valid_in  : std_logic := '0';
  signal d_out     : std_logic_vector(C_OUT_BW-1 downto 0);
  signal valid_out : std_logic;
    
  --upisujemo vrednosti za kasnije poredjenje sa fajlom, to radimo zbog pajplajna, 
  --ne mozemo direktno kao kod sekvencijalnog, da citamo odma na isti takt iz fajla
  -- mi ustvari, svaki put kad se kaze da je validan rezultat, 
  type t_exp_arr is array (0 to 1023) of std_logic_vector(C_OUT_BW-1 downto 0);
  signal exp_mem : t_exp_arr := (others => (others => '0'));
  signal wr_ptr  : integer := 0;
  signal rd_ptr  : integer := 0;

  signal done_sending : std_logic := '0';

begin

  clk <= not clk after C_CLK_PERIOD/2;
  
  UUT: entity work.sqrt_pipelined
    generic map (
      G_IN_BW    => C_IN_BW,
      G_OUT_BW   => C_OUT_BW,
      G_OUT_FRAC => C_OUT_FRAC
    )
    port map (
      clk       => clk,
      reset     => reset,
      d_in      => d_in,
      valid_in  => valid_in,
      d_out     => d_out,
      valid_out => valid_out
    );

  STIMULUS : process
    file fin  : text;
    file fout : text;
    variable l_in, l_out : line;
    variable v_in  : bit_vector(C_IN_BW-1 downto 0);
    variable v_out : bit_vector(C_OUT_BW-1 downto 0);
  begin
    file_open(fin,  "sqrt_input.txt",  read_mode);
    file_open(fout, "sqrt_output.txt", read_mode);

    reset <= '1';
    wait for C_CLK_PERIOD;
    reset <= '0';
    wait until rising_edge(clk);

    while not endfile(fin) loop
      readline(fin, l_in);
      read(l_in, v_in);

      readline(fout, l_out);
      read(l_out, v_out);
      
      --na din prosledjujemo podatke iz ulaznog fajla
      d_in <= to_stdlogicvector(v_in);
      valid_in <= '1';
      
      -- u niz sa ocekivanim rezultatima upisuje 
      exp_mem(wr_ptr) <= to_stdlogicvector(v_out);
      wr_ptr <= wr_ptr + 1;

      wait until rising_edge(clk);
    end loop;

    valid_in <= '0';
    d_in <= (others => '0');
    done_sending <= '1';

    wait;
  end process STIMULUS;

  CHECK_PROC : process(clk) is
  begin
    if rising_edge(clk) then
      if valid_out = '1' then
        assert d_out = exp_mem(rd_ptr)
          report "GRESKA: d_out="
                 & to_hstring(to_bitvector(d_out))
                 & " ocekivano="
                 & to_hstring(to_bitvector(exp_mem(rd_ptr)))
          severity error;

        rd_ptr <= rd_ptr + 1;
      end if;

      if done_sending = '1' and rd_ptr = wr_ptr then
        report "PIPELINED SQRT TEST USPESNO ZAVRSEN"
        severity note;

        assert false
            report "END OF SIMULATION"
        severity failure;

      end if;
    end if;
  end process CHECK_PROC;

end architecture tb;
