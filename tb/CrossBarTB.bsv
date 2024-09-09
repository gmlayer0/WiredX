package CrossBarTB;

import XArbiter::*;
import FIFO::*;
import Vector::*;
import GetPut::*;
import CrossBar::*;
import LFSR::*;
import LCGR::*;

typedef 5 NUM_MASTER;
typedef 4 NUM_SLAVE;

module mkMyArb(XArbiter#(NUM_MASTER, Bit#(8)));
    XArbiter#(NUM_MASTER, Bit#(8)) arb <- mkXArbiter(False);
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
    Reg#(Int#(32)) req_cnt[valueOf(NUM_MASTER)] <- mkCReg(valueOf(NUM_MASTER), 0);
    Reg#(Int#(32)) rsp_cnt[valueOf(NUM_SLAVE)]  <- mkCReg(valueOf(NUM_SLAVE), 0);

    for(Integer i = 0 ; i < valueOf(NUM_MASTER) ; i = i + 1) begin
        Reg#(Bit#(32)) rndValue <- mkReg(pack(lcg(fromInteger(i))));
        rule upd_rndValue;
            rndValue <= pack(lcg(unpack(rndValue)));
        endrule
        rule gen_random_request(iter < 15);
            Bit#(4) myIndex = fromInteger(i);
            Bit#(8) myValue = {myIndex, rndValue[5:2]};
            Bit#(2) index = myValue[1:0];
            mst[i].put(myValue);
            req_cnt[i] <= req_cnt[i] + 1;
            $display("%05d - %03d::MST%01d: %h, Requesting SLV%d",req_cnt[i] , iter ,i ,myValue , index);
        endrule
    end
    for(Integer i = 0 ; i < valueOf(NUM_SLAVE) ; i = i + 1) begin
        rule consume_request;
            let consumeValue <- slv[i].get();
            rsp_cnt[i] <= rsp_cnt[i] + 1;
            $display("%05d - %03d::SLV%01d: Got %h",rsp_cnt[i] ,iter ,i ,consumeValue);
        endrule
    end

endmodule

endpackage : CrossBarTB