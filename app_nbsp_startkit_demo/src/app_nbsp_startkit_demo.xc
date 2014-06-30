/**
 * Copyright: 2014, Errsu. All rights reserved.
 *
 * NBSP Startkit demo
 * ==================
 *
 * Demonstrates the non-blocking bidirectional small packet protocol.
 *
 * Each virtual core runs a player holding the state and calculating the PWM
 * for a single LED. The players are linked by a ring of channels running
 * the NBSP protocol.
 *
 * The NBSP message exchange is shown by circulating virtual lights,
 * in that each player hands over the light to the neighbour after counting
 * down the brightness of the light to 50%. To show bidirectionality, two
 * lights are circulated in opposite directions. The LED brightness is the
 * sum of the brightnesses of the two lights.
 *
 * A second set of channels forms a token ring. This allows to collect the
 * LED states 256 times per PWM period to transport them to the single core
 * that drives all physical LEDs through the 32-bit port.
 *
 * The first player sends out a token to the ring to collect the on/off states
 * of all LEDs from the other players, and on receiption of the filled token
 * updates the P32A port. To make things not too easy, the order of players
 * in the token ring is different to the one that transports the virtual lights.
 * Also, the token ring runs at maximum speed. Finally, the token is used to count
 * down the brightness of the lights, so there are no timers used in the program.
 *
 * The achieved PWM period is about 1.3kHz, so the token ring runs at a speed
 * of about 330k cycles per second, or 380 ns per handover, including
 * circulating lights and PWM calculation.
 *
 * The topology of both channel rings is shown in topology.jpg in the app folder.
 */

#include <xs1.h>
#include <platform.h>
#include "nbsp.h"

#define LED_A1 0x80000
#define LED_B1 0x40000
#define LED_C1 0x20000
#define LED_A2 0x01000
#define LED_B2 0x00800
#define LED_C2 0x00400
#define LED_A3 0x00200
#define LED_B3 0x00100
#define LED_C3 0x00080

port p32 = XS1_PORT_32A;

static void player(
  unsigned led,
  chanend c_token_in,
  chanend c_token_out,
  chanend c_left,
  chanend c_right,
  port? p32)
{
  unsigned led_brightness = 0; // 0 ... 256
  unsigned led_pwm_phase = 0;  // 0 ... 255

  unsigned left_to_right_count = 0; // 1024 ... 0
  unsigned right_to_left_count = 0; // 128 ... 0

  t_nbsp_state state_token_in;
  t_nbsp_state state_token_out;
  t_nbsp_state state_left;
  t_nbsp_state state_right;

  unsigned buffer_token_out[2];
  unsigned buffer_left[2];
  unsigned buffer_right[2];

  nbsp_init(state_token_in, 0);  // pure input channel, no buffer needed
  nbsp_init(state_token_out, 2);
  nbsp_init(state_left, 2);
  nbsp_init(state_right, 2);

  if (!isnull(p32))
  {
    // player with port starts token and two circulating lights
    nbsp_send(c_token_out, state_token_out, buffer_token_out, 0);
    nbsp_send(c_right, state_right, buffer_right, 0);
    nbsp_send(c_left, state_left, buffer_left, 0);
  }

  while(1)
  {
    select
    {
      case nbsp_receive_msg(c_token_in, state_token_in):
      {
        if (nbsp_handle_msg(c_token_in, state_token_in, null))
        {
          // token ring collects LED on/off states

          unsigned token = nbsp_received_data(state_token_in);

          if (led_pwm_phase < led_brightness)
          {
            token |= led; // set own LED bit
          }

          if (!isnull(p32))
          {
            // player with port consumes old token and starts new one
            p32 <: ~token; // 1 => LED OFF, 0 => LED ON
            token = 0;
          }

          nbsp_send(c_token_out, state_token_out, buffer_token_out, token);

          led_pwm_phase = (led_pwm_phase + 1) % 256;

          if (led_pwm_phase == 0)
          {
            // two circulating lights are updated after each PWM cycle

            if (left_to_right_count > 0)
            {
              if (--left_to_right_count == (256 / 2))
              {
                // ask right player to turn on light
                nbsp_send(c_right, state_right, buffer_right, 0);
              }
            }

            if (right_to_left_count > 0)
            {
              if (--right_to_left_count == (2048 / 2))
              {
                // ask left player to turn on light
                nbsp_send(c_left, state_left, buffer_left, 0);
              }
            }

            // show superposition of two rotating lights
            led_brightness = (left_to_right_count >> 1) + (right_to_left_count >> 4);
          }
        }
        break;
      }
      case nbsp_receive_msg(c_token_out, state_token_out):
      {
        if (nbsp_handle_msg(c_token_out, state_token_out, buffer_token_out))
        {
          // no incoming data expected, just handle the acks for outgoing data
        }
        break;
      }
      case nbsp_receive_msg(c_left, state_left):
      {
        if (nbsp_handle_msg(c_left, state_left, buffer_left))
        {
          left_to_right_count = 256; // left player asked to turn on LED (rotates fast)
        }
        break;
      }
      case nbsp_receive_msg(c_right, state_right):
      {
        if (nbsp_handle_msg(c_right, state_right, buffer_right))
        {
          right_to_left_count = 2048; // right player asked to turn on LED (rotates slowly)
        }
        break;
      }
    }
  }
}

int main()
{
  // token ring collecting LED on/off states
  chan ct1, ct2, ct3, ct4, ct5, ct6, ct7, ct8;

  // bidirectional ring circulating the lights
  chan cx1, cx2, cx3, cx4, cx5, cx6, cx7, cx8;

  par {
    on tile[0]: player(LED_B1, ct8, ct1, cx8, cx1, p32);
    on tile[0]: player(LED_C1, ct1, ct2, cx1, cx2, null);
    on tile[0]: player(LED_C2, ct3, ct4, cx2, cx3, null);
    on tile[0]: player(LED_C3, ct6, ct7, cx3, cx4, null);
    on tile[0]: player(LED_B3, ct5, ct6, cx4, cx5, null);
    on tile[0]: player(LED_A3, ct4, ct5, cx5, cx6, null);
    on tile[0]: player(LED_A2, ct2, ct3, cx6, cx7, null);
    on tile[0]: player(LED_A1, ct7, ct8, cx7, cx8, null);
  }
  return 0;
}
