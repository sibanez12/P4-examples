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

/*
 *  Implement a decaying counter
 */

typedef bit<32> uint_t;

const uint_t DECAY_RATE = 10;

// This control block is executed deterministically every 1ns
@periodic(1ns)
control counter_decay(in bool timer_trigger,
                      in uint_t sample,
                      out uint_t result)
{
    // externs
    register<uint_t>(1) counter_reg;

    // metadata
    uint_t counter;

    apply {
        if (timer_trigger) {
            sample = 0;
        }
        @atomic {
            counter = counter_reg.read();
            counter = (counter |+| sample) |-| DECAY_RATE;
            counter_reg.write(counter);
        }
        result = counter;
    }
}

