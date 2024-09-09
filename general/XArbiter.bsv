package XArbiter;

import Vector::*;
import Arbiter::*;

interface XArbiterClient #(type data_t);
    method Action request(data_t payload);
    method Bool grant();
endinterface

interface XArbiter #(numeric type mst_num, type data_t);
    interface Vector#(mst_num, XArbiterClient#(data_t)) clients;
    method Bit#(TLog#(mst_num)) grant_id;
endinterface

module mkXArbiter #(Bool fixed) (XArbiter #(mst_num, data_t));
    Arbiter_IFC#(mst_num) arb <- mkArbiter(fixed);

    Vector#(mst_num, XArbiterClient#(data_t)) ifs = ?;
    for(Integer m = 0 ; m < valueOf(mst_num) ; m = m + 1) begin
        ifs[m] = (
            interface XArbiterClient#(data_t);
                method Action request(data_t payload);
                    arb.clients[m].request;
                endmethod

                method Bool grant;
                    return arb.clients[m].grant;
                endmethod
            endinterface
        );
    end
    interface clients = ifs;
    method grant_id = arb.grant_id;

endmodule
endpackage : XArbiter
