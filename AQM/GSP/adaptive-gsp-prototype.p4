/*
Copyright 2018 Stanford University
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

#include <core.p4>
#include <v1model.p4>

/*
 * Global Synchronization Protection (GSP) algorithm is described in
 * the following paper:
 *     https://ieeexplore.ieee.org/abstract/document/7483103
 *
 * Things needed to implement adaptive GSP:
 *   - atomic operations on state
 *   - exactly one pkt per cycle to properly manage state and track qdepth
 *   - instantaneous queue sizes
 *   - approximate division operation
 *   - the last time the buffer dropped a packet as a result of overflow
 *   - (optional) estimated queueing delay
 */

typedef bit<9> queueId_t;
typedef bit<14> queueDepth_t;

typedef bit<32> uint_t;
/*
 * The following bitwidth is a parameter that can be adjusted to make
 * the division operation more or less accurate.
 */
typedef bit<10> log_uint_t;

/* number of ns between consecutive packets */
const uint_t PKT_TIME = 1;

/* Possible states of the packet drop rate PI controller */
typedef bit<2> state_t; 
const state_t STABLE = 0;
const state_t WAIT_EMPTY = 1;
const state_t WAIT_THRESH = 2;

extern buffer {
    buffer();
    queueDepth_t get_qsize(in queueId_t index);
    uint_t get_last_drop_time(in queueId_t index);
}

// The above code would likely become part of some standard file to
// #include here.

typedef bit<48>  EthernetAddress;

header Ethernet_h {
    EthernetAddress dstAddr;
    EthernetAddress srcAddr;
    bit<16>         etherType;
}

struct Parsed_packet {
    Ethernet_h    ethernet;
}

struct metadata_t {
    bit<1> unicast;
    queueId_t qid;
    bit<1> null_pkt; // indicates if this is a null packet for background operations
}

parser parserI(packet_in pkt,
               out Parsed_packet hdr,
               inout metadata_t meta,
               inout standard_metadata_t stdmeta) {
    state start {
        pkt.extract(hdr.ethernet);
        transition accept;
    }
}

control DeparserI(packet_out packet,
                  in Parsed_packet hdr) {
    apply { packet.emit(hdr.ethernet); }
}

control cIngress(inout Parsed_packet hdr,
                 inout metadata_t meta,
                 inout standard_metadata_t stdmeta)
{
    // externs
    buffer() buffer_inst;
    register<uint_t>(1) maxTime_reg;
    register<uint_t>(1) thresh_reg;
    register<uint_t>(1) time_above_thresh_reg;
    register<uint_t>(1) time_below_thresh_reg;
    register<state_t>(1) alg_state_reg;
    register<uint_t>(1) presetInt_reg;
    register<uint_t>(1) expiry_reg;

    // metadata
    queueDepth_t qdepth;
    uint_t maxTime;
    uint_t thresh;
    uint_t time_above_thresh;
    uint_t time_below_thresh;
    state_t alg_state;
    uint_t log_alpha;
    uint_t log_tau;
    uint_t presetInt;

    // controls
    divide_pipe() divide;

    apply {

        /*
         * Compute output port and decide if packet should be dropped
         * for reasons other than congestion at the egress link.
         * Not shown for brevity.
         */

        qdepth = buffer_inst.get_qsize(meta.qid);
        thresh = thresh_reg.read();
        now = meta.ingress_global_timestamp;
        maxTime = maxTime_reg.read();
        presetInt = presetInt_reg.read();

        /* 
         * NOTE: We require that this apply block be executed exactly
         * once every PKT_TIME (or clock cycle). To do this, we will
         * assume that the architecture supports a programmable packet
         * generator that is able to fill all "empty" clock cycles with
         * a "null" packet. 
         */

        /*
         * State machine to update the state of the algorithm. If a
         * packet is dropped as a result of a buffer overflow then
         * the control loop to update the packet drop rate becomes
         * unstable. The GSP paper says:
         * """
         * we suspend the accumulation of time_below_threshold right after
         * a buffer overflow and resume it again after the queue has
         * completed the cycle from buffer overflow to empty to above
         * threshold.
         * """
         * A couple of things to note:
         *   (1) This is a fairly complicated atomic operation
         *   (2) This must be executed exactly once every PKT_TIME
         *       (or clock cycle) in order to track the qdepth and 
         *       perform state transitions correctly.
         */
        @atomic {
            alg_state = alg_state_reg.read();
            state_t next_state = alg_state; // default: stay in same state
            last_drop = buffer_inst.get_last_drop_time(meta.qid);

            if (alg_state == STABLE) {
                if (now - last_drop < (PKT_TIME<<2) ) {
                    // a buffer overflow occured recently
                    next_state = WAIT_EMPTY;
                }
            }
            else if (alg_state == WAIT_EMPTY) {
                if (qdepth == 0) {
                    next_state = WAIT_THRESH;
                }
            }
            else if (alg_state == WAIT_THRESH) {
                if (qdepth >= thresh) {
                    next_state = STABLE;
                }
            }
            // update state
            alg_state_reg.write(next_state);
        }

        /*
         * Here we accumulate the time_above_thresh and time_below_thresh.
         * Note that this logic must be run exactly once every PKT_TIME
         * (or clock cycle) in order to correctly accumulate the times.
         * If the logic is only executed upon arrival of legit packets
         * we have no way of knowing when the qdepth crossed the threshold
         * and hence can't update the state properly.
         *
         * If left unchecked these state variables would continue to
         * accumulate and would eventually wrap or saturate. In order
         * to fix this note that the difference:
         *   (alpha*time_above_thresh - time_below_thresh)
         * is the only thing that matters as far as the algorithm is
         * concerned. So we can reset the values in the individual
         * registers as long as we don't affect this difference.
         * We don't do that here, but note that it can be done.
         */
        @atomic {
            time_above_thresh = time_above_thresh_reg.read();
            time_below_thresh = time_below_thresh_reg.read();
            if (qdepth > thresh) {
                time_above_thresh_reg.write(time_above_thresh + PKT_TIME);
            }
            else if (qdepth < thresh && next_state == STABLE) {
                time_below_thresh_reg.write(time_below_thresh + PKT_TIME);
            }
        }

        /*
         * Run the actual adapative GSP algorithm only on legit packets
         * i.e. not the null background packets
         */
        if (!meta.null_pkt) {
            /*
             * compute: cumulTime += alpha * time_above_thresh - time_below_thresh
             * where cumulTime has a lower bound of 0 and an upper bound of maxTime.
             * We will assume alpha is a power of 2 so we can use a bit shift.
             */
            @atomic {
                old_cumulTime = cumulTime_reg.read();
                // use saturating subtraction to ensure that cumulTime "sticks"
                // at 0 rather than wrapping around
                cumulTime = (old_cumulTime + (time_above_thresh << log_alpha)) |-| time_below_thresh;
                if (cumulTime > maxTime) {
                    cumulTime = maxTime;
                }
                cumulTime_reg.write(cumulTime);
            }

            /*
             * compute: interval = presetInt / (1 + cumulTime/tau)
             */
            divide.apply(presetInt, 1 + (cumulTime >> log_tau), interval);

            /*
             * Run basic GSP
             */
            @atomic {
                if ((qdepth > thresh) && (now > expiry_reg.read())) {
                    expiry_reg.write(now + interval);
                    mark_to_drop();
                }
            }
        }
        else {
            // drop null packets
            mark_to_drop();
        }
    }
}

/*
 * Here we will use lookup tables to approximate integer division.
 * We will use the following useful fact:
 *     A/B = exp(log(A) - log(B))
 * We will use ternary tables to approximate log() and exact match
 * tables to implement exp()
 * See this paper for more details:
 *     https://homes.cs.washington.edu/~arvind/papers/flexswitch.pdf
 */
control divide_pipe(in uint_t numerator,
                    in uint_t demoninator,
                    out uint_t result) {

    log_uint_t log_num;
    log_uint_t log_denom;
    log_uint_t log_result;

    action set_log_num(log_unit_t result) {
        log_num = result;
    }

    table log_numerator {
        key = { numerator: ternary; }
        actions = { set_log_num; }
        size = 1024;
        default_action = set_log_num(0);
    }

    action set_log_denom(log_unit_t result) {
        log_denom = result;
    }

    table log_denominator {
        key = { denominator: ternary; }
        actions = { set_log_denom; }
        size = 1024;
        default_action = set_log_denom(0);
    }

    action set_result(uint_t result) {
        result = result;
    }

    table exp {
        key = { log_result: exact; }
        actions = { set_result; }
        size = 2048;
        default_action = set_result(0);
    }

    apply {
        // numerator / denominator = exp(log(numerator) - log(denominator))
        if (numerator == 0 || denominator == 0 || denominator > numerator) {
            result = 0;
        } else {
            log_numerator.apply();
            log_denominator.apply();
            log_result = log_num - log_denom;
            exp.apply();
        }
    }
}

control cEgress(inout Parsed_packet hdr,
                inout metadata_t meta,
                inout standard_metadata_t stdmeta) {
    apply { }
}

control vc(inout Parsed_packet hdr,
           inout metadata_t meta) {
    apply { }
}

control uc(inout Parsed_packet hdr,
           inout metadata_t meta) {
    apply { }
}

V1Switch(parserI(),
    vc(),
    cIngress(),
    cEgress(),
    uc(),
    DeparserI()) main;
