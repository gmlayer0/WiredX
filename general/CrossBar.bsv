package CrossBar;

import Vector::*;
import GetPut::*;
import Arbiter::*;
import FIFO::*;

// Build a crossbar between multiple master and slave.
// Routing Policy and Arbiter Policy is flexable.

// Latency is fixed for now.

module mkCrossbarBridge #(
    function Bit#(slv_num) getRoute(mst_index_t mst, data_t payload),
    module #(Arbiter_IFC#(mst_num)) mkArb,
    Vector#(mst_num, Get#(data_t)) mst_if,
    Vector#(slv_num, Put#(data_t)) slv_if
)(Empty) provisos(
    Alias#(mst_index_t, Bit#(TLog#(mst_num))),
    Bits#(data_t, data_size),
    FShow#(data_t)
);

    // For each master, create a decoder to determine which slave to fire on.
    Reg#(Maybe#(Bit#(slv_num))) mst_slv_dec[valueOf(mst_num)][2];
    Reg#(data_t) mst_slv_payload[valueOf(mst_num)][2];

    // For each slave, Create a Arbiter.
    Arbiter_IFC#(mst_num) arb[valueOf(slv_num)];
    Vector#(slv_num, Wire#(Bit#(mst_num))) slv_grant <- replicateM(mkDWire(0));

    for(Integer m = 0 ; m < valueOf(mst_num) ; m = m + 1) begin
        mst_slv_dec[m] <- mkCReg(2, Invalid);
        mst_slv_payload[m] <- mkCReg(2, ?);
        rule decode_mst_target(!isValid(mst_slv_dec[m][0]));
            let payload <- mst_if[m].get;
            let slv_dec = getRoute(fromInteger(m), payload);
            mst_slv_dec[m][0] <= Valid (slv_dec);
            mst_slv_payload[m][0] <= payload;
        endrule

        rule mst_inner_handshake;
            Bool handshaked = False;
            for(Integer s = 0 ; s < valueOf(slv_num) ; s = s + 1) begin
                handshaked = unpack(slv_grant[s][m]) || handshaked;
            end
            if(handshaked) mst_slv_dec[m][1] <= Invalid;
        endrule
    end

    // For each slave, Create a decoder to determine which master to catch from.
    for(Integer s = 0 ; s < valueOf(slv_num) ; s = s + 1) begin
        
        // Skid buffer for slv put
        Reg#(Maybe#(data_t)) slv_tmp[2] <- mkCReg(2, Invalid);

        // Arbiter
        arb[s] <- mkArb;
        
        // Requester
        for(Integer m = 0 ; m < valueOf(mst_num) ; m = m + 1) begin
            rule req_arbiter(
                slv_tmp[0] matches tagged Invalid &&&
                mst_slv_dec[m][1] matches tagged Valid .vec
            );
                if(unpack(vec[s])) arb[s].clients[m].request();
            endrule
        end
        
        // Arbiter grant
        rule grant_arbiter;
            if(arb[s].clients[arb[s].grant_id].grant()) begin
                Bit#(mst_num) mst_sel = 0;
                slv_tmp[0] <= tagged Valid mst_slv_payload[arb[s].grant_id][1];
                mst_sel[arb[s].grant_id] = 1'b1;
                slv_grant[s] <= mst_sel;
            end
        endrule

        // Put to slv port
        rule put_slave(slv_tmp[1] matches tagged Valid .payload);
            slv_if[s].put(payload);
            slv_tmp[1] <= Invalid;
        endrule
    end

endmodule

module mkCrossbarIntf#(
    function Bit#(slv_num) getRoute(mst_index_t mst, data_t payload),
    module #(Arbiter_IFC#(mst_num)) mkArb
)(
    Tuple2#(Vector#(mst_num, Put#(data_t)), Vector#(slv_num, Get#(data_t)))
) provisos(
    Alias#(mst_index_t, Bit#(TLog#(mst_num))),
    Bits#(data_t, data_size),
    FShow#(data_t)
);

    Vector#(mst_num, FIFO#(data_t)) mst_q <- replicateM(mkFIFO);
    Vector#(slv_num, FIFO#(data_t)) slv_q <- replicateM(mkFIFO);

    mkCrossbarBridge(getRoute, mkArb, map(fifoToGet, mst_q), map(fifoToPut, slv_q));
    return tuple2(map(fifoToPut, mst_q), map(fifoToGet, slv_q));
endmodule

endpackage : CrossBar