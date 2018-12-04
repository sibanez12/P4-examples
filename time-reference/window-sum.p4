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
 * Compute sum over a sliding window 
 */

typedef bit<32> uint_t;

const uint_t NUM_SAMPLES = 64;
const uint_t LOG_NUM_SAMPLES = 6;

/*
 * The @always(PERIOD [, default_values]) annotation indicates that
 * this control block is executed deterministically every PERIOD.
 * If the control block has any inputs then default values must be
 * supplied.
 */
@always(1ns, sample=0)
control window_sum(in uint_t sample,
                   out uint_t result)
{
    // externs
    register<uint_t>(1) sum_reg;
    shift_register<uint_t> (NUM_SAMPLES) shift_reg;

    // metadata
    uint_t sum;
    uint_t out_sample;

    apply {
        @atomic(100ns) {
            sum = sum_reg.read();
            sum = sum |+| sample;
            out_sample = shift_reg.shift(sample);
            sum = sum |-| out_sample;
            sum_reg.write(sum);
        }
        result = sum;
    }
}

