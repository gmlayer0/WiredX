package LCGR;

    function UInt#(32) lcg (UInt#(32) x);
        return 1103515245 * x + 12345;
    endfunction

endpackage : LCGR