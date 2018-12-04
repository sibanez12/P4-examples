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
 *  Implement a register array that can be reset in the data-plane.
 *  Could be useful to implement a bloom filter.
 *  If reset is indicated then this will iterate through all
 *  possible indicies and reset each entry in the register
 *  array to 0.
 */

#define NUM_ENTRIES 64

typedef bit<1> opCode_t; // READ=0, WRITE=1
typedef bit<1> state_t;  // IDLE=0, RESET=1 
typedef bit<32> index_t;
typedef bit<32> uint_t;

const opCode_t READ = 0;
const opCode_t WRITE = 1;

const state_t WRITE = 0;
const state_t RESET = 1;

// This control block is executed deterministically every 1ns
@always(1ns, opCode=READ, index=0, value=0, reset=false)
control register_reset(in opCode_t opCode,  // READ or WRITE
                       in index_t index,    // index to access
                       in uint_t value,     // value to write
                       in bool reset,       // reset the register
                       out uint_t result)   // final value at my_reg[index]
{
    // externs
    register<state_t>(1) state_reg;
    register<uint_t>(NUM_ENTRIES) my_reg;
    register<index_t>(1) index_reg;

    // metadata
    state_t cur_state;
    state_t next_state;
    uint_t reg_val;

    apply {
        // Determine the next state (and index if in RESET state)
        @atomic {
            state_reg.read(cur_state, 0);
            next_state = cur_state; // default: stay in same state

            if (cur_state == IDLE) {
                if (reset) {
                    next_state = RESET;
                }
            }
            else if (cur_state == RESET) {
                index_reg.read(index, 0);
                if (index == NUM_ENTRIES-1) {
                    next_state = IDLE;
                    index = 0;
                }
                else {
                    index = index + 1;
                }
                index_reg.write(0, index);
            }
            // update state
            state_reg.write(0, next_state);
        }

        // Access the main register
        @atomic {
            my_reg.read(reg_val, index);
            if (cur_state == IDLE) {
                if (opCode == READ) {
                    result = reg_val;
                }
                else { // opCode == WRITE
                    result = value;
                }
            }
            else {  // cur_state == RESET
                result = 0;
            }
            my_reg.write(index, result);
        }
    }
}

