package CrossBar;

import Vector::*;
import GetPut::*;
import XArbiter::*;
import FIFO::*;
import Connectable::*;

// Build a crossbar between multiple master and slave.
// Routing Policy and Arbiter Policy is flexable.

// Latency is fixed for now.
module mkCrossbarIntf#(
    function Bit#(slv_num) getRoute(mst_index_t mst, data_t payload),
    module #(XArbiter#(mst_num, data_t)) mkArb
)(
    Tuple2#(Vector#(mst_num, Put#(data_t)), Vector#(slv_num, Get#(data_t)))
) provisos(
    Alias#(mst_index_t, Bit#(TLog#(mst_num))),
    Bits#(data_t, data_size),
    FShow#(data_t)
);
    // Creating Interface vector.
    Vector#(mst_num, Put#(data_t)) mst_intf = ?;
    Vector#(slv_num, Get#(data_t)) slv_intf = ?;

    // For each master, create a decoder to determine which slave to fire on.
    Reg#(Maybe#(Bit#(slv_num))) mst_slv_dec[valueOf(mst_num)][2];
    Reg#(data_t) mst_slv_payload[valueOf(mst_num)][2];

    // For each slave, Create a Arbiter.
    XArbiter#(mst_num, data_t) arb[valueOf(slv_num)];
    Vector#(slv_num, Wire#(Bit#(mst_num))) slv_grant <- replicateM(mkDWire(0));

    for(Integer m = 0 ; m < valueOf(mst_num) ; m = m + 1) begin
        mst_slv_dec[m] <- mkCReg(2, Invalid);
        mst_slv_payload[m] <- mkCReg(2, ?);

        Wire#(Bool) mst_barrier <- mkWire;

        mst_intf[m] = (
        interface Put#(data_t);
            method Action put(data_t payload);
                let slv_dec = getRoute(fromInteger(m), payload);
                if(mst_barrier) begin
                    mst_slv_dec[m][0] <= Valid (slv_dec);
                    mst_slv_payload[m][0] <= payload;
                end
            endmethod
        endinterface
        );
        rule mst_barrier_handle(!isValid(mst_slv_dec[m][0]));
            mst_barrier <= True;
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
                if(unpack(vec[s])) arb[s].clients[m].request(mst_slv_payload[m][1]);
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
        Wire#(Bool) slv_barrier <- mkWire;
        slv_intf[s] = (
        interface Get#(data_t);
            method ActionValue#(data_t) get();
                let payload = slv_tmp[1];
                if(slv_barrier) slv_tmp[1] <= Invalid;
                return fromMaybe(unpack(?), payload);
            endmethod
        endinterface
        );
        rule slv_barrier_handler(slv_tmp[1] matches tagged Valid .payload);
            slv_barrier <= True;
        endrule
    end

    return tuple2(mst_intf, slv_intf);

endmodule

module mkCrossbarConnect #(
    function Bit#(slv_num) getRoute(mst_index_t mst, data_t payload),
    module #(XArbiter#(mst_num, data_t)) mkArb,
    Vector#(mst_num, Get#(data_t)) mst_if,
    Vector#(slv_num, Put#(data_t)) slv_if
)(Empty) provisos(
    Alias#(mst_index_t, Bit#(TLog#(mst_num))),
    Bits#(data_t, data_size),
    FShow#(data_t)
);

    Tuple2#(Vector#(mst_num, Put#(data_t)),Vector#(slv_num, Get#(data_t))) intf <- mkCrossbarIntf(getRoute, mkArb);
    match {.mst, .slv} = intf;
    for(Integer m = 0 ; m < valueOf(mst_num) ; m = m + 1) mkConnection(mst[m], mst_if[m]);
    for(Integer s = 0 ; s < valueOf(slv_num) ; s = s + 1) mkConnection(slv[s], slv_if[s]);

endmodule

endpackage : CrossBar