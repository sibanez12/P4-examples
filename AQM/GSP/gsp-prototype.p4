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
 * Things needed to implement basic GSP:
 *   - atomic operations on state
 *   - instantaneous queue sizes
 */

typedef bit<9> queueId_t;
typedef bit<14> queueDepth_t;

typedef bit<32> uint_t;

extern buffer {
    buffer();
    queueDepth_t get_qsize(in queueId_t index);
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
    register<uint_t>(1) thresh_reg;
    register<uint_t>(1) expiry_reg;
    /* statically configured to be: 
     * "two times the RTT of the traffic that is expected to dominate the queue" */
    register<uint_t>(1) interval_reg;

    // metadata
    queueDepth_t qdepth;
    uint_t thresh;
    uint_t interval;

    apply {

        /*
         * Compute output port and decide if packet should be dropped
         * for reasons other than congestion at the egress link.
         * Not shown for brevity.
         */

        qdepth = queue_depth_inst.read(meta.qid);
        thresh = thresh_reg.read();
        interval = interval_reg.read();
        now = meta.ingress_global_timestamp;

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
