package Crossbar;

import Vector::*;
import GetPut::*;
import Arbiter::*;

// Build a crossbar between multiple master and slave.
// Routing Policy and Arbiter Policy is flexable.

// Latency is fixed for now.

module mkCrossbarCore #(
    function Bit#(slv_num) getRoute(mst_index_t mst, data_t payload),
    module (Arbiter_IFC#(mst_num) arb_if) mkArb,
    Vector#(mst_num, Get#(data_t)) mst_if,
    Vector#(slv_num, Put#(data_t)) slv_if
)(Empty) provisos(
    Alias#(mst_index_t, Bit#(TLog#(mst_num))),
    Bits#(data_t, data_size),
    FShow#(data_t)
);

    // For each master, create a decoder to determine which slave to fire on.
    Reg#(Maybe#(Bit#(slv_num))) mst_slv_ids[valueOf(mst_num)][2];
    Reg#(data_t) mst_slv_payload[valueOf(mst_num)][2];

    // For each slave, Create a Arbiter.
    Arbiter_IFC#(mst_num) arb[valueOf(slv_num)];

    for(Integer i = 0 ; i < valueOf(mst_num) ; i = i + 1) begin
        mst_slv_ids[i] <- mkCReg(2, Invalid);
        mst_slv_payload[i] <- mkCReg(2, ?);
        rule decode_mst_target(!isValid(mst_slv_ids[i][0]));
            let payload <- mst_if[i].get;
            let slv_dec = getRoute(fromInteger(i), payload);
            mst_slv_ids[i][0] <= Valid (slv_dec);
            mst_slv_payload[i][0] <= payload;
        endrule

        rule mst_grants;
            for(Integer s = 0 ; s < valueOf(slv_num) ; s += 1) begin
                if(arb[s].clients[i].grant()) mst_slv_ids[i][1] <= Invalid;
            end
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
                slv_tmp[0] matches tagged Invalid &&
                mst_slv_ids[m][1] matches tagged Valid .vec
            ) begin
                if(vec[s]) arb[s].clients[m].request();
            end
        end
        
        // Arbiter grant
        rule grant_arbiter();
            for(Integer m = 0 ; m < valueOf(mst_num) ; m = m + 1)
                if(arb[s].clients[m].grant()) begin
                    slv_tmp[0] <= mst_slv_payload[m][1];
            end
        endrule

        // Put to slv port
        rule put_slave(slv_tmp[1] matches tagged Valid .payload);
            slv_if[s].put(payload);
            slv_tmp[1] <= Invalid;
        endrule
    end

endmodule

endpackage : Crossbar