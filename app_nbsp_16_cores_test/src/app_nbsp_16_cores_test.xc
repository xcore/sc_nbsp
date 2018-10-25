/**
 * Copyright: 2014, Errsu. All rights reserved.
 *
 * NBSP 16 Cores Test
 * ==================
 *
 * Measures the average and maximum select loop cycle period
 * of 16 cores running on 2 tiles, connected by 32 channels.
 * 24 channels are local (same tile), 8 channels run cross-tile.
 * The topology is shown in topology.jpg in the app folder.
 *
 * Each core is sending/receiving messages in both directions over
 * 4 channels, busy-waiting (sleeping) for different-per-core
 * periods in between.
 *
 * After sending and receiving a predefined number of WORDS_TO_SEND,
 * each core prints the maximum and average time spend in the
 * cycles of the while(1)/select loop. The results show that
 * the communication is indeed non-blocking.
 *
 * Running the measurements in xsim, with CHECK_FOR_PROGRAMMING_ERRORS
 * set to 0 in nbsp.xc, reveals the following results:
 *
 * max: 1780 ns, avg: 610 ns
 * max: 2170 ns, avg: 900 ns
 * max: 1750 ns, avg: 760 ns
 * max: 2170 ns, avg: 930 ns
 * max: 1670 ns, avg: 910 ns
 * max: 2140 ns, avg: 890 ns
 * max: 1790 ns, avg: 830 ns
 * max: 2140 ns, avg: 480 ns
 * max: 2070 ns, avg: 770 ns
 * max: 1750 ns, avg: 930 ns
 * max: 2160 ns, avg: 930 ns
 * max: 1800 ns, avg: 840 ns
 * max: 1740 ns, avg: 580 ns
 * max: 1730 ns, avg: 910 ns
 * max: 1820 ns, avg: 920 ns
 * max: 1790 ns, avg: 920 ns
 */

#include <xs1.h>
#include <platform.h>
#include <stdio.h>

#include "nbsp.h"

#define TEST_IN_SIMULATOR 1

#if TEST_IN_SIMULATOR
#define WORDS_TO_SEND 100
#else
#define WORDS_TO_SEND 100000
#endif

static void sleep(timer t, unsigned microseconds)
{
  unsigned time;
  t :> time;
  time += (microseconds * 100);
  t when timerafter(time) :> void;
}

static void send_some_words(chanend c, t_nbsp_state& state, unsigned b[], unsigned& sn, unsigned amount)
{
  for (unsigned i = 0; i < amount; i++)
  {
    nbsp_send(c, state, b, sn++);
  }
}

static void handle_msg(chanend c, t_nbsp_state& state, unsigned b[], unsigned& sn, unsigned& rn)
{
  if (nbsp_handle_msg(c, state, b))
  {
    unsigned data = nbsp_received_data(state);
    if (data != rn++)
    {
      printf("unexpected data: %d\n", data);
    }
    if (sn < WORDS_TO_SEND && nbsp_sending_capacity(state) > 0)
    {
      nbsp_send(c, state, b, sn++);
    }
  }
}

void player(chanend c1, chanend c2, chanend c3, chanend c4, unsigned sleep_time)
{
  timer t;

  t_nbsp_state s1, s2, s3, s4;
  unsigned b1[16];
  unsigned b2[32];
  unsigned b3[64];
  unsigned b4[128];
  unsigned sn1, sn2, sn3, sn4;
  unsigned rn1, rn2, rn3, rn4;

  nbsp_init(s1, 16);
  nbsp_init(s2, 32);
  nbsp_init(s3, 64);
  nbsp_init(s4, 128);

  // let the other tile initialize
#if !TEST_IN_SIMULATOR
  sleep(t, 30000);
#endif

  // initial synchronisation
  outct(c1, XS1_CT_END);
  outct(c2, XS1_CT_END);
  outct(c3, XS1_CT_END);
  outct(c4, XS1_CT_END);
  chkct(c1, XS1_CT_END);
  chkct(c2, XS1_CT_END);
  chkct(c3, XS1_CT_END);
  chkct(c4, XS1_CT_END);

  sn1 = 0;
  sn2 = 0;
  sn3 = 0;
  sn4 = 0;

  send_some_words(c1, s1, b1, sn1, 10);
  send_some_words(c2, s2, b2, sn2, 20);
  send_some_words(c3, s3, b3, sn3, 30);
  send_some_words(c4, s4, b4, sn4, 40);

  rn1 = 0;
  rn2 = 0;
  rn3 = 0;
  rn4 = 0;

  unsigned max_blocking_time = 0;
  unsigned total_blocking_time = 0;
  unsigned blocking_count = 0;

  while (1)
  {
    sleep(t, sleep_time);

    unsigned start, end;
    t :> start;

    select
    {
      case nbsp_receive_msg(c1, s1):
      {
        handle_msg(c1, s1, b1, sn1, rn1);
        break;
      }
      case nbsp_receive_msg(c2, s2):
      {
        handle_msg(c2, s2, b2, sn2, rn2);
        break;
      }
      case nbsp_receive_msg(c3, s3):
      {
        handle_msg(c3, s3, b3, sn3, rn3);
        break;
      }
      case nbsp_receive_msg(c4, s4):
      {
        handle_msg(c4, s4, b4, sn4, rn4);
        break;
      }
      default:
      {
        // all requested words are sent in handle_msg
        // the idle job just checks if we are done

        if (sn1 == WORDS_TO_SEND && nbsp_pending_words_to_send(s1) == 0 && rn1 == WORDS_TO_SEND
         && sn1 == WORDS_TO_SEND && nbsp_pending_words_to_send(s2) == 0 && rn2 == WORDS_TO_SEND
         && sn1 == WORDS_TO_SEND && nbsp_pending_words_to_send(s3) == 0 && rn3 == WORDS_TO_SEND
         && sn1 == WORDS_TO_SEND && nbsp_pending_words_to_send(s4) == 0 && rn4 == WORDS_TO_SEND)
        {
#if !TEST_IN_SIMULATOR
          sleep(t, 5000000); // let the others finish
#endif
          unsigned avg = total_blocking_time / blocking_count;
          printf("max: %d ns, avg: %d ns\n", max_blocking_time * 10, avg * 10);
          return;
        }
        break;
      }
    }

    t :> end;
    unsigned blocking_time = end - start;

    if (blocking_time > max_blocking_time)
    {
      max_blocking_time = blocking_time;
    }
    total_blocking_time += blocking_time;
    blocking_count++;
  }
}

int main()
{
  chan c1,  c2,  c3,  c4,  c5,  c6,  c7,  c8;
  chan c9, c10, c11, c12, c13, c14, c15, c16;
  chan c17, c18, c19, c20, c21, c22, c23, c24;
  chan c25, c26, c27, c28, c29, c30, c31, c32;

  par {
    on tile[0]: player(c1,  c4,  c21, c30, 1); // 1
    on tile[0]: player(c1,  c2,  c5,  c22, 2); // 2
    on tile[0]: player(c2,  c3,  c6,  c23, 3); // 3
    on tile[0]: player(c3,  c7,  c24, c30, 4); // 4
    on tile[0]: player(c4,  c8,  c25, c32, 3); // 5
    on tile[0]: player(c5,  c8,  c9,  c26, 4); // 6
    on tile[0]: player(c6,  c9,  c10, c27, 1); // 7
    on tile[0]: player(c7,  c10, c28, c32, 2); // 8

    on tile[1]: player(c11, c14, c21, c29, 5); // 9
    on tile[1]: player(c11, c12, c15, c22, 3); // 10
    on tile[1]: player(c12, c13, c16, c23, 1); // 11
    on tile[1]: player(c13, c17, c24, c29, 2); // 12
    on tile[1]: player(c14, c18, c25, c31, 3); // 13
    on tile[1]: player(c15, c18, c19, c26, 4); // 14
    on tile[1]: player(c16, c19, c20, c27, 5); // 15
    on tile[1]: player(c17, c20, c28, c31, 1); // 16
  }

  return 0;
}
