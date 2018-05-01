// log base 2
function [31:0] log2;
    input reg [31:0] value;
    begin
        value = value - 1;
        for (log2 = 0; value > 0; log2 = log2 + 1)
        begin
            value = value >> 1;
        end
    end
endfunction
