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
 *  Implement a token bucket
 */

typedef bit<32> uint_t;

const uint_t FILL_RATE = 10; // tokens / slot
const uint_t MAX_TOKENS = 1000;

// This control block is executed deterministically every 1ns
@periodic(1ns)
control token_bucket(in bool timer_trigger,
                     in uint_t request, // number of requested tokens
                     out bool result)
{
    // externs
    register<uint_t>(1) tokens_reg;

    // metadata
    uint_t tokens;

    apply {
        if (timer_trigger) {
            request = 0;
        }
        @atomic {
            tokens = tokens_reg.read();
            // update tokens
            tokens = tokens + FILL_RATE;
            if (tokens > MAX_TOKENS) {
                tokens = MAX_TOKENS;
            }
            // check request
            if (tokens > request) {
                result = true;
                tokens = tokens - request;
            }
            else {
                result = false;
            }
            tokens_reg.write(tokens);
        }
    }
}

