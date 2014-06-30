/**
 * Copyright: 2014, Errsu. All rights reserved.
 *
 * NBSP performance test
 * =====================
 *
 * Measures the throughput of a single NBSP channel in the following 4 modes:
 *   - oneway without buffering
 *   - oneway with buffering
 *   - oneway with maximum performance (no buffering, no select statement,
 *     assuming no data in opposite direction, not counting received data,
 *     received data is tested for start/end conditions though)
 *   - bidirectional (receiver is echoing received data, with the sender
 *     being 16 - buffered - messages ahead)
 *
 * All modes are tested with a receiver on the same tile and a receiver
 * on the other tile. All unused threads are busy, which can be changed
 * by setting RUN_AT_62_MIPS to 0, so that the senders and receivers run
 * at 125 MIPS (assuming 500MHz processor clock).
 *
 * Running the measurements with CHECK_FOR_PROGRAMMING_ERRORS set to 0
 * in nbsp.xc, and RUN_AT_62_MIPS set to 1, reveals the following results:
 *
 * receive-buffered---same-tile  1000 words in 1121310 ns == 3483 kbyte/s
 * receive-unbuffered-same-tile  1000 words in  927790 ns == 4209 kbyte/s
 * receive-fast-------same-tile  1000 words in  839800 ns == 4651 kbyte/s
 * bidirect-buffered-same-tile  2x500 words in  941940 ns == 4146 kbyte/s
 * receive-buffered---cross-tile 1000 words in 1203190 ns == 3246 kbyte/s
 * receive-unbuffered-cross-tile 1000 words in 1075620 ns == 3630 kbyte/s
 * receive-fast-------cross-tile 1000 words in  995650 ns == 3922 kbyte/s
 * bidirect-buffered-cross-tile 2x500 words in  950530 ns == 4109 kbyte/s
 */

#include <xs1.h>
#include <platform.h>
#include <stdio.h>

#include "nbsp.h"

#define WORDS_TO_SEND 1000

void send_generic(chanend c, unsigned buffer_occupation)
{
  t_nbsp_state state;
  unsigned buffer[64];

  nbsp_init(state, 64);

  outct(c, XS1_CT_END); // synchronise with receiver
  chkct(c, XS1_CT_END);

  nbsp_send(c, state, buffer, 0); // first
  for (unsigned i = 0; i < buffer_occupation; i++)
  {
    nbsp_send(c, state, buffer, 1);
  }

  unsigned words_to_send = WORDS_TO_SEND - 2 - buffer_occupation;

  while(words_to_send-- > 0)
  {
    select
    {
      case nbsp_receive_msg(c, state):
      {
        if (nbsp_handle_msg(c, state, buffer))
        {
          printf("unexpected data from receiver\n");
        }
        else
        {
          nbsp_send(c, state, buffer, 1); // next
        }
        break;
      }
    }
  }

  nbsp_send(c, state, buffer, 2); // last
  nbsp_flush(c, state, buffer);
}

void send_fast(chanend c)
{
  t_nbsp_state state;
  unsigned buffer[2];

  nbsp_init(state, 2);

  outct(c, XS1_CT_END); // synchronise with receiver
  chkct(c, XS1_CT_END);

  nbsp_send(c, state, buffer, 0); // first
  unsigned words_to_send = WORDS_TO_SEND - 2;

  while(words_to_send-- > 0)
  {
    nbsp_receive_msg(c, state);        // nothing else to wait for
    nbsp_handle_msg(c, state, buffer); // assumes to receive ack only
    nbsp_send(c, state, buffer, 1);    // more
  }

  nbsp_send(c, state, buffer, 2); // last
  nbsp_flush(c, state, buffer);
}

void send_bidirectional(chanend c, unsigned remote)
{
  t_nbsp_state state;
  unsigned buffer[64];

  nbsp_init(state, 64);

  outct(c, XS1_CT_END); // synchronise with receiver
  chkct(c, XS1_CT_END);

  unsigned n_sent = 0;
  unsigned n_rcvd = 0;

  timer t;
  unsigned start, end;
  t :> start;

  for (unsigned i = 0; i < 16; i++)
  {
    nbsp_send(c, state, buffer, n_sent++); // preload buffer
  }

  while(n_rcvd < WORDS_TO_SEND / 2)
  {
    select
    {
      case nbsp_receive_msg(c, state):
      {
        if (nbsp_handle_msg(c, state, buffer))
        {
          n_rcvd++;
        }
        else
        {
          if (n_sent < WORDS_TO_SEND / 2)
          {
            nbsp_send(c, state, buffer, n_sent++);
          }
        }
        break;
      }
    }
  }

  t :> end;
  printf("bidirect-buffered-%s 2x%d words in %7d ns == %d kbyte/s\n",
    remote ? "cross-tile" : "same-tile ",
    n_rcvd,
    (end - start) * 10,
    ((400000000 / (end - start)) * n_rcvd * 2) / 1024);
}

void receive_generic(chanend c, unsigned remote, unsigned using_buffer)
{
  timer t;
  unsigned start, end;

  t_nbsp_state state;
  nbsp_init(state, 0);

  outct(c, XS1_CT_END); // synchronise with sender
  chkct(c, XS1_CT_END);

  unsigned received_words = 0;

  while(1)
  {
    select
    {
      case nbsp_receive_msg(c, state):
      {
        if (nbsp_handle_msg(c, state, null))
        {
          unsigned data = nbsp_received_data(state);
          received_words++;

          if (data == 0)
          {
            t :> start;
          }
          else if (data == 2)
          {
            t :> end;
            printf("receive-%s-%s %d words in %7d ns == %d kbyte/s\n",
              using_buffer ? "buffered--" : "unbuffered",
              remote ? "cross-tile" : "same-tile ",
              received_words,
              (end - start) * 10,
              ((400000000 / (end - start)) * received_words) / 1024);
            return;
          }
        }
        else
        {
          printf("unexpected ack in receiver\n");
        }
        break;
      }
    }
  }
}

void receive_fast(chanend c, unsigned remote)
{
  timer t;
  unsigned start, end;

  t_nbsp_state state;
  nbsp_init(state, 0);

  outct(c, XS1_CT_END); // synchronise with sender
  chkct(c, XS1_CT_END);

  while(1)
  {
    nbsp_receive_msg(c, state);
    nbsp_handle_msg(c, state, null);
    unsigned data = nbsp_received_data(state);

    if (data == 0)
    {
      t :> start;
    }
    else if (data == 2)
    {
      t :> end;
      printf("receive-fast-------%s %d words in %7d ns == %d kbyte/s\n",
        remote ? "cross-tile" : "same-tile ",
        WORDS_TO_SEND,
        (end - start) * 10,
        ((400000000 / (end - start)) * WORDS_TO_SEND) / 1024);
      return;
    }
  }
}

void receive_bidirectional(chanend c)
{
  t_nbsp_state state;
  unsigned buffer[64];

  nbsp_init(state, 64);

  outct(c, XS1_CT_END); // synchronise with sender
  chkct(c, XS1_CT_END);

  unsigned received_words = 0;

  while(received_words < WORDS_TO_SEND / 2)
  {
    select
    {
      case nbsp_receive_msg(c, state):
      {
        if (nbsp_handle_msg(c, state, buffer))
        {
          unsigned data = nbsp_received_data(state);
          received_words++;
          nbsp_send(c, state, buffer, data);
        }
        break;
      }
    }
  }

  nbsp_flush(c, state, buffer);
}

int main()
{
  chan c_local;
  chan c_remote;

  par {
    on tile[0]:
    {
      send_generic(c_local, 16);
      send_generic(c_local, 0);
      send_fast(c_local);
      send_bidirectional(c_local, 0);
      send_generic(c_remote, 16);
      send_generic(c_remote, 0);
      send_fast(c_remote);
      send_bidirectional(c_remote, 1);
    }
    on tile[0]:
    {
      receive_generic(c_local, 0, 1);
      receive_generic(c_local, 0, 0);
      receive_fast(c_local, 0);
      receive_bidirectional(c_local);
      while (1); // make sure sender is not faster when testing remote
    }

    on tile[1]:
    {
      receive_generic(c_remote, 1, 1);
      receive_generic(c_remote, 1, 0);
      receive_fast(c_remote, 1);
      receive_bidirectional(c_remote);
    }
    on tile[1]: while (1);

    // busy threads limiting the performance

    #define RUN_AT_62_MIPS 1 // set to 0 to run at 125 MIPS

    on tile[0]: while (RUN_AT_62_MIPS);
    on tile[0]: while (RUN_AT_62_MIPS);
    on tile[0]: while (RUN_AT_62_MIPS);
    on tile[0]: while (RUN_AT_62_MIPS);
    on tile[0]: while (RUN_AT_62_MIPS);
    on tile[0]: while (RUN_AT_62_MIPS);

    on tile[1]: while (RUN_AT_62_MIPS);
    on tile[1]: while (RUN_AT_62_MIPS);
    on tile[1]: while (RUN_AT_62_MIPS);
    on tile[1]: while (RUN_AT_62_MIPS);
    on tile[1]: while (RUN_AT_62_MIPS);
    on tile[1]: while (RUN_AT_62_MIPS);
  }

  return 0;
}
