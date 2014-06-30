/**
 * Copyright: 2014, Errsu. All rights reserved.
 *
 * Simple NBSP Example
 * ===================
 *
 * Two players residing on different tiles take care for their respective ports.
 * Any change on an input port is reported to the other player, who changes
 * it's own output port value accordingly. 
 * Thanks to NBSP only two logical cores and one channel are needed.
 */

#include <xs1.h>
#include <platform.h>
#include "nbsp.h"

void player(chanend c, in port pin, out port pout)
{
  t_nbsp_state state;
  unsigned buffer[16];
  nbsp_init(state, 16);

  unsigned vin = 0;
  pout <: 0;
    
  while (1)
  {
    select
    {
      case nbsp_receive_msg(c, state):
      {
        if (nbsp_handle_msg(c, state, buffer))
        {
          pout <: nbsp_received_data(state);
        }
        break;
      }
      case pin when pinsneq(vin) :> vin:
      {
        if (!nbsp_send(c, state, buffer, vin))
        {
          // buffer overflow: input value change ommitted
        }
        break;
      }
    }
  }
}

on tile [0]: in  port pa0 = XS1_PORT_1A;
on tile [0]: out port pb0 = XS1_PORT_1B;
on tile [1]: in  port pa1 = XS1_PORT_1A;
on tile [1]: out port pb1 = XS1_PORT_1B;

int main()
{
  chan c;

  par {
    on tile[0]: player(c, pa0, pb0);
    on tile[1]: player(c, pa1, pb1);
  }

  return 0;
}
