package CrossBarTB;

import Arbiter::*;
import FIFO::*;
import Vector::*;
import GetPut::*;
import CrossBar::*;
import LFSR::*;

typedef 7 NUM_MASTER;
typedef 4 NUM_SLAVE;

module mkMyArb(Arbiter_IFC#(NUM_MASTER));
    Arbiter_IFC#(NUM_MASTER) arb <- mkArbiter(False);
    return arb;
endmodule

function Bit#(NUM_SLAVE) myRouter(Bit#(3) mst_idx, Bit#(8) data);
    Bit#(4) sel = 0;
    sel[data[1:0]] = 1;
    return sel;
endfunction

typedef Tuple2#(Vector#(NUM_MASTER, Put#(Bit#(8))), Vector#(NUM_SLAVE, Get#(Bit#(8)))) XBAR_INTF;

(* synthesize *)
module mkSynCrossBar(XBAR_INTF);
    XBAR_INTF intf <- mkCrossbarIntf(myRouter, mkMyArb);
    return intf;
endmodule

(* synthesize *)
module mkTB();

    Reg#(Int#(32)) iter <- mkReg(1);
    LFSR#(Bit#(32)) lfsr <- mkLFSR_32;
    rule tick;
        iter <= iter + 1;
        if(iter > 20) $finish();
    endrule

    rule update_lfsr;
        lfsr.next();
    endrule

    // Generate CrossBar
    let intf <- mkSynCrossBar;
    match {.mst, .slv} = intf;

    for(Integer i = 0 ; i < valueOf(NUM_MASTER) ; i = i + 1) begin
        rule gen_random_request;
            Bit#(32) lfsrValue = pack(iter * 31 * (fromInteger(i) * 5));
            Bit#(4) myIndex = fromInteger(i);
            Bit#(8) myValue = {myIndex, lfsrValue[3:0]};
            Bit#(2) index = myValue[1:0];
            mst[i].put(myValue);
            $display("%03d::MST%01d: %h, Requesting SLV%d", iter ,i ,myValue , index);
        endrule
    end
    for(Integer i = 0 ; i < valueOf(NUM_SLAVE) ; i = i + 1) begin
        rule consume_request;
            let consumeValue <- slv[i].get();
            $display("%03d::SLV%01d: Got %h",iter ,i ,consumeValue);
        endrule
    end

endmodule

endpackage : CrossBarTB