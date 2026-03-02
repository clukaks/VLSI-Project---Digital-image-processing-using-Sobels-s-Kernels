library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;
library work;
use work.RAM_definitions_PK.all;

entity im_ram is
    generic (
        G_RAM_WIDTH : integer := 8;            		    -- Specify RAM data width
        G_RAM_DEPTH : integer := 256*256; 				        -- Specify RAM depth (number of entries)
        G_RAM_PERFORMANCE : string := "LOW_LATENCY"   -- Select "HIGH_PERFORMANCE" or "LOW_LATENCY" 
    );
    port (
        addra : in std_logic_vector((clogb2(G_RAM_DEPTH)-1) downto 0);     -- Write address bus, width determined from RAM_DEPTH
        addrb : in std_logic_vector((clogb2(G_RAM_DEPTH)-1) downto 0);     -- Read address bus, width determined from RAM_DEPTH
        dina  : in std_logic_vector(G_RAM_WIDTH-1 downto 0);		  -- RAM input data
        clka  : in std_logic;                       			  -- Clock
        wea   : in std_logic;                       			  -- Write enable
        enb   : in std_logic;                       			  -- RAM Enable, for additional power savings, disable port when not in use
        rstb  : in std_logic;                       			  -- Output reset (does not affect memory contents)
        regceb: in std_logic;                       			  -- Output register enable
        doutb : out std_logic_vector(G_RAM_WIDTH-1 downto 0) 		  -- RAM output data
    );
end im_ram;

architecture Behavioral of im_ram is
    signal doutb_reg : std_logic_vector(G_RAM_WIDTH-1 downto 0) := (others => '0');
    type ram_type is array (0 to G_RAM_DEPTH-1) of std_logic_vector (G_RAM_WIDTH-1 downto 0);          -- 2D Array Declaration for RAM signal
    signal ram_data : std_logic_vector(G_RAM_WIDTH-1 downto 0) ;
    
    -- The folowing code either initializes the memory values to a specified file or to all zeros to match hardware
    impure function initramfromfile (ramfilename : in string) return ram_type is
        file ramfile	: text; -- is in ramfilename;
        variable ramfileline : line;
         variable ram_name	: ram_type;
        variable bitvec : bit_vector(G_RAM_WIDTH-1 downto 0);
    begin
        file_open(ramfile, ramfilename, read_mode);
        for i in ram_type'range loop
            readline (ramfile, ramfileline);
            read (ramfileline, bitvec);
            ram_name(i) := to_stdlogicvector(bitvec);
        end loop;
        return ram_name;
    end function;
    
    impure function init_from_file_or_zeroes(ramfile : string) return ram_type is
    begin
        if ramfile /= "" then
            return InitRamFromFile(ramfile) ;
        else
            return (others => (others => '0'));
        end if;
    end;
    
    -- Define RAM
    signal ram_name : ram_type := init_from_file_or_zeroes("cameraman.dat");
    
begin
    --Insert the following in the architecture after the begin keyword
    process(clka)
    begin
        if(clka'event and clka = '1') then
            if(wea = '1') then
                ram_name(to_integer(unsigned(addra))) <= dina;
            end if;
            if(enb = '1') then
                ram_data <= ram_name(to_integer(unsigned(addrb)));
            end if;
        end if;
    end process;
    
    --  Following code generates LOW_LATENCY (no output register)
    --  Following is a 1 clock cycle read latency at the cost of a longer clock-to-out timing
    
    no_output_register : if G_RAM_PERFORMANCE = "LOW_LATENCY" generate
        doutb <= ram_data;
    end generate;
    
    --  Following code generates HIGH_PERFORMANCE (use output register)
    --  Following is a 2 clock cycle read latency with improved clock-to-out timing
    
    output_register : if G_RAM_PERFORMANCE = "HIGH_PERFORMANCE"  generate
    process(clka)
    begin
        if(clka'event and clka = '1') then
            if(rstb = '1') then
                doutb_reg <= (others => '0');
            elsif(regceb = '1') then
                doutb_reg <= ram_data;
            end if;
        end if;
    end process;
    doutb <= doutb_reg;
    end generate;

end Behavioral;
