
#ifndef _SIMPLE_ARCH_P4_
#define _SIMPLE_ARCH_P4_

struct sume_meta_t {...}

// Define the events supported by this architecture
/*
 * The Ingress event defines all the inputs required to invoke the Parser.
 */
event Ingress(packet_in p,
              sume_meta_t sume_meta);

/*
 * The InvokePipe and Drop events each define all the inputs required to
 * invoke the Pipe.
 */
event InvokePipe<H, M>(H headers,
                       M drop_meta,
                       sume_meta_t sume_meta);
/*
 * The format of the drop_meta bus is defined by the P4 programmer and its
 * fields are populated within the ingress pipeline. The architecture will
 * use this metadata bus to construct Drop events.
 */
event Drop<H, M>(H headers,
                 M drop_meta,
                 sume_meta_t sume_meta);

/*
 * The InvokeDeparser event defines all the inputs required to invoke the
 * Deparser.
 */
event InvokeDeparser<H, M>(H headers,
                           M drop_meta,
                           sume_meta_t sume_meta);

// Define the top-level architecture elements
parser Parser<H, M>(packet_in         p,
                    inout sume_meta_t sume_meta,
                    out H             headers,
                    out M             drop_meta);

control Pipe<H, M>(inout H           headers,
                   inout M           drop_meta,
                   inout sume_meta_t sume_meta);

control Deparser<H, M>(in H              headers,
                       in M              drop_meta,
                       inout sume_meta_t sume_meta,
                       packet_out        p);

package SimpleArch<H, M> (Parser<H, M> p,
                          Pipe<H, M> map,
                          Deparser<H, M> d) {

    // The set of events supported by the architecture
    events = {
        Ingress,
        InvokePipe<H,M>,
        Drop<H,M>,
        InvokeDeparser<H,M>
    };

    /*
     * Updated P4 concurrency model:
     *   "Each parser or control block is executed as a separate thread to handle
     *    events occurring in the architecture."
     *
     * The architecture's job is to process events. Each time instant
     * the architecture checks for valid events and kicks off the appropriate
     * processing thread(s).
     */
    always@(events) {
        if (Ingress.isValid()) {
            /* The apply() statement kicks off a new thread which executes
             * asynchronously in the background.
             */
            p.apply(Ingress);
            /* The emit() statement creates a new event whose parameters are bound
             * to the outputs of the apply()'ed parser/control.
             * The new event will become valid once the background thread (created
             * by the above statement) completes.
             */
            emit(InvokePipe(p.headers, p.drop_meta, p.sume_meta));
        }
        if (InvokePipe.isValid() || Drop.isValid()) {
            bool legit_pkt = InvokePipe.isValid();
            // events can be combined using bitwise OR
            // an invalid event will have a bit representation of all 0's
            map.apply(InvokePipe | Drop);
            if (legit_pkt) {
                // only invoke the deparser for legit packets
                emit(InvokeDeparser(map.headers, map.drop_meta, map.sume_meta));
            }
        }
        if (InvokeDeparser.isValid()) {
            d.apply(InvokeDeparser);
        }
    }

}

#endif  /* _SIMPLE_ARCH_P4_ */
