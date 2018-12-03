/**
 * Copyright: 2014-2017, Errsu. All rights reserved.
 *
 */

#include "nbsp.h"

// NBSP - non-blocking bidirectional small package protocol
//
// - the protocol is symmetric, both sides send and receive simultaneously
// - data is sent in 32 bit pieces because they are easy to handle by the HW
// - the sender sends a DATA token, followed by an unsigned int and a PAUSE token
// - the receiver replies with an END token
// - therefore, each player waits for either a DATA token or an END token:
//   (a) DATA token: data word follows, nbsp_handle_msg returns 1
//   (b) END token: acknowledgement was received, nbsp_handle_msg returns 0
// - the PAUSE token closes the connection to prevent congestion
// - the sender waits for an acknowledgement before sending more data,
//   so the data to be sent is buffered on the sender side
// - since no player sends more than one data packet (6 bytes) and
//   one ack packet (1 byte), there are no more than 7 bytes in the
//   queue for each player, and since the FIFO size is not less than 8 bytes,
//   no player is ever blocked waiting for a peer

void nbsp_init(t_nbsp_state& state, unsigned buffer_size)
{
#if CHECK_FOR_PROGRAMMING_ERRORS
  if ((buffer_size & (buffer_size - 1)) != 0 || buffer_size == 1)
  {
    printf("nbsp error: buffer size must be zero or a power of 2 greater than 1\n");
  }
#endif
  state.words_to_be_acknowledged = 0;
  state.read_index  = 0;
  state.write_index = 0;
  state.buffer_mask = buffer_size - 1;
}

static void send_data(chanend c, unsigned data)
{
  outct(c, NBSP_CT_DATA);
  outuint(c, data);
}

static void send_ack(chanend c)
{
  outct(c, XS1_CT_END);
}

unsigned nbsp_handle_msg(chanend c, t_nbsp_state& state, unsigned (&?buffer)[])
{
  if (state.msg_is_ack)
  {
#if CHECK_FOR_PROGRAMMING_ERRORS
    if (isnull(buffer))
    {
      printf("nbsp error: sending side must provide buffer to nbsp_handle_msg\n");
      return 0;
    }
    if (state.words_to_be_acknowledged == 0)
    {
      printf("nbsp error: unexpected ack\n");
    }
#endif
    outct(c, XS1_CT_PAUSE);
    if (state.read_index != state.write_index)
    {
      // there is more data to send
      unsigned data = buffer[state.read_index];
      state.read_index = (state.read_index + 1) & state.buffer_mask;
      send_data(c, data);
    }
    else
    {
      state.words_to_be_acknowledged = 0;
    }
    return 0; // no data received
  }
  else
  {
    send_ack(c);
    return 1; // did receive data
  }
}

unsigned nbsp_send(chanend c, t_nbsp_state& state, unsigned buffer[], unsigned data)
{
  if (state.words_to_be_acknowledged == 0)
  {
    // buffer must be empty, we can immediately send, no need for buffering
    send_data(c, data);
    state.words_to_be_acknowledged = 1;
    return 1;
  }
  else
  {
#if CHECK_FOR_PROGRAMMING_ERRORS
    if (state.buffer_mask == 0xFFFFFFFF)
    {
      printf("nbsp error: nbsp_send needs nonzero buffer size\n");
    }
#endif
    // busy sending, must buffer the data
    unsigned next_write_index = (state.write_index + 1) & state.buffer_mask;

    if (next_write_index != state.read_index)
    {
      buffer[state.write_index] = data;
      state.write_index = next_write_index;
      return 1;
    }
    else
    {
      // buffer has no room, data is not sent
      return 0;
    }
  }
}

unsigned nbsp_pending_words_to_send(t_nbsp_state& state)
{
  return
    ((state.write_index - state.read_index + state.buffer_mask + 1) & state.buffer_mask) +
    state.words_to_be_acknowledged;
}

unsigned nbsp_sending_capacity(t_nbsp_state& state)
{
  unsigned pending = nbsp_pending_words_to_send(state);
  return state.buffer_mask + 1 - pending;
}

void nbsp_flush(chanend c, t_nbsp_state& state, unsigned buffer[])
{
  while(state.words_to_be_acknowledged)
  {
    select
    {
      case nbsp_receive_msg(c, state):
      {
        if (nbsp_handle_msg(c, state, buffer))
        {
#if CHECK_FOR_PROGRAMMING_ERRORS
          printf("nbsp error: unexpected data while flushing sender\n");
#endif
        }
        break;
      }
    }
  }
}

void nbsp_uddw_flush(chanend c, t_nbsp_state& state, unsigned buffer[])
{
  while(state.words_to_be_acknowledged)
  {
    select
    {
      case nbsp_uddw_handle_ack(c, state, buffer):
      {
        break;
      }
    }
  }
}

void nbsp_handle_outgoing_traffic(chanend c, t_nbsp_state& state, unsigned buffer[], unsigned available_tens_of_ns)
{
  // timed idle function for pure data senders

  // all timings in tens of ns at 62.5 MIPS
  #define TIME_TO_START  44 // call the function and setup the timer
  #define TIME_TO_LOOP   23 // enter the loop and select
  #define TIME_TO_FINISH 95 // receive and handle a message, get the timeout and return

  #define MIN_AVAILABLE (TIME_TO_START + TIME_TO_LOOP + TIME_TO_FINISH)

#if CHECK_FOR_PROGRAMMING_ERRORS
  if (available_tens_of_ns < MIN_AVAILABLE)
  {
    printf("nbsp error: handle_outgoing_traffic needs at least %d tens of nanoseconds\n",
      MIN_AVAILABLE);
  }
#endif

  timer t;
  unsigned time;

  t :> time;
  time += (available_tens_of_ns - (TIME_TO_START + TIME_TO_FINISH));

  while(state.words_to_be_acknowledged)
  {
    select
    {
      case nbsp_receive_msg(c, state):
      {
        if (nbsp_handle_msg(c, state, buffer))
        {
#if CHECK_FOR_PROGRAMMING_ERRORS
          printf("nbsp error: unexpected data in pure sender\n");
#endif
        }
        break;
      }
      case t when timerafter(time) :> void:
      {
        return;
      }
    }
  }
}
