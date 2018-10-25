/**
 * Copyright: 2014-2017, Errsu. All rights reserved.
 */

#ifndef __nbsp_h__
#define __nbsp_h__

#include <platform.h>

#define CHECK_FOR_PROGRAMMING_ERRORS 0

#if CHECK_FOR_PROGRAMMING_ERRORS
#include <stdio.h>
#endif

// NBSP - non-blocking bidirectional small package protocol
// ========================================================
//
// Overview
// --------
//
// The basic idea for this protocol originates from the USB-Audio 2.0
// Device Reference Design by XMOS, where 32-bit MIDI messages are sent
// over a channel. The sender, before sending the next message, waits
// for an acknowledgement from the receiver. Pending data on the sender
// side is buffered. Both the sender and receiver thread do other things
// in parallel in a select loop.
//
// The NBSP module puts this principle into an easy-to-use library,
// including buffering and automatic acknowledgement. Also, the
// protocol on the channel has been modified to avoid network congestion,
// so many more channels can be used in parallel than in the USB-Audio
// reference design. The library is designed to be as symmetrical as
// the protocol, where both ends of the communication channel, called
// players, get into the role of senders, receivers, or both, just
// at the moment when they send or receive data.
//
// The NBSP implementation presents itself as five basic functions:
//
// void nbsp_init(state, buffer_size)
//     Initializes the protocols state machine for this player,
//     remembers the buffer size.
//
// unsigned nbsp_send(chanend, state, buffer, data)
//     Sends the data to the channel. If the channel is busy,
//     the data is stored in the buffer. If the buffer is full,
//     the data is discarded and 0 is returned. Otherwise, if
//     the data was sent or stored, 1 is returned.
//
// void nbsp_receive_msg(chanend, state)
//     Waits for an incoming message, which can be data or an acknowledgement.
//     This is a select handler and therefore does not return a value.
//
// unsigned nbsp_handle_msg(chanend, state, buffer)
//     Does everything required by the protocol to handle the received message.
//     If an acknowledgement was received, the next pending data from
//     the buffer - if any - is sent to the channel and 0 is returned.
//     If data was received, it is stored in the state, an acknowledgement
//     is sent and 1 is returned.
//
// unsigned nbsp_received_data(state)
//     Returns the last word of data received.
//
// These functions can be used in different ways to achieve unidirectional
// or bidirectional, blocking or non-blocking operation. How to achieve
// these behaviors is described in detail in the following paragraphs.
//
// Additionally, there are a few auxilliary and convenience functions:
//
// unsigned nbsp_pending_words_to_send(state)
//     Returns the number of data words which are still in the buffer or the
//     channel, i.e. which are not yet acknowledged by the receiver.
//
// unsigned nbsp_sending_capacity(state)
//     Returns the guaranteed number of words that currently can be sent
//     without nbsp_send returning 0.
//
// void nbsp_flush(chanend, state, buffer)
//     Blocks until all data in the buffer has been sent and
//     was acknowledged by the receiver.
//
// void nbsp_handle_outgoing_traffic(chanend, state, buffer, available_time)
//     Just like nbsp_flush, with the difference that it returns after
//     the given available time has passed.
//
//
// Preparations
// ------------
//
// To work with an NBSP channel, the following preparations
// are done on each side:
//
// void player(chanend c, ...) // the protocol works on regular channels
// {
//   t_nbsp_state state;  // this holds the protocol state and received data
//   unsigned buffer[2];  // the buffer holds data to be sent, the buffer size
//                        // in 32-bit words must be 2 or more, and a power of two, the
//                        // buffer capacity is actually one less than the buffer size
//   nbsp_init(state, 2); // resets the protocol state and declares the buffer size
//   ...
// }
//
// It is also possible to work without a buffer, if the player
// is a pure receiver of data and does not send data itself:
//
// void receiver(chanend c, ...) // we will receive data over the channel
// {
//   t_nbsp_state state;  // this holds the protocol state and received data
//   nbsp_init(state, 0); // resets the protocol state and declares that we have no buffer
//   ...
// }
//
// Sending data and handling acknowledgements
// ------------------------------------------
//
// To send a word of data, do this:
//
//   unsigned data = ...;
//   nbsp_send(c, state, buffer, data);
//
// If the channel is busy, the data is stored in the buffer and
// automatically sent when the receiver acknowledged the previous data.
//
// nbsp_send returns 0 if the channel is busy *and* the buffer
// is full and therefore the data could not be stored for later delivery.
//
// As you already might have understood, it's not sufficient for a sender
// to send the data, it's also necessary to regularly check for acknowledgements,
// otherwise the data will remain stuck in the send buffer.
//
// There are different ways to wait for acknowledgements.
// A typical non-blocking way is is to regularly call
// nbsp_receive_msg and nbsp_handle_message:
//
//   select
//   {
//     case nbsp_receive_msg(c, state):
//     {
//       if (!nbsp_handle_msg(c, state, null))
//       {
//         // ack received, you might want to nbsp_send here,
//         // especially if a previous nbsp_send returned 0
//       }
//       break;
//     }
//     default:
//       break; // continue with other tasks if no messages were received
//   }
//
// If you want to stay for a certain time in such a select loop,
// you might use nbsp_handle_outgoing_traffic, which runs for
// the given time, but returns when no more data is to be sent.
//
//   nbsp_handle_outgoing_traffic(c, state, buffer, 10000); // run for 1 ms
//
// To block until all data has been sent and acknowledged
// by the receiver, call
//
//   nbsp_flush(c, state, buffer);
//
// If you expect a bidirectional communication, then checking for
// acks and receiving data is done at the same time. Such a mixed
// communication is actually a more typical way to use NBSP than
// the pure senders or receivers. But before we come to bidirectional
// communication, let's first have a look at data receiption.
//
// Receiving data
// --------------
//
// To receive a word of data, the following sequence of calls is needed:
//
//   nbsp_receive_msg(c, state):          // waits for an incoming message
//   if (nbsp_handle_msg(c, state, null)) // sends ack and returns 1 if data was received
//   {
//     unsigned data = nbsp_received_data(state); // access the data saved in state
//       ....
//   }
//
// Such a call of nbsp_receive_msg would block until data is received.
// Therefore, it is usually used in a select statement:
//
//   select
//   {
//     case nbsp_receive_msg(c, state):
//     {
//       if (nbsp_handle_msg(c, state, null))
//       {
//         unsigned data = nbsp_received_data(state); // access the data saved in state
//         ....
//       }
//       break;
//     }
//     default:
//       break; // continue if no messages were received
//   }
//
// As you can see, this select statement is very similiar to the
// one mentioned above in the part about handling acknowledgements,
// it just uses the other leg of the if (nbsp_handle_msg) .. else
// statement.
//
// To receive more data, regularly enter such a select statement.
//
// Receiving data from multiple channels
// -------------------------------------
//
// A typical situation is where data from multple channels and other
// sources is received in a single while/select loop:
//
//   while(1)
//   {
//     select
//     {
//       case nbsp_receive_msg(c1, state1):
//       {
//         if (nbsp_handle_msg(c1, state1, buffer1))
//         {
//           unsigned data_from_c1 = nbsp_received_data(state1);
//           <use data from c1>
//         }
//         break;
//       }
//       case nbsp_receive_msg(c2, state2):
//       {
//         if (nbsp_handle_msg(c2, state2, buffer2))
//         {
//           unsigned data_from_c2 = nbsp_received_data(state2);
//           <use data from c2>
//         }
//         break;
//       }
//       case <other events>:
//       {
//         <handle other events>
//         break;
//       }
//     }
//   }
//
// Bidirectional communication
// ---------------------------
//
// A communication in both directions is nothing more than the combination
// of the code for sending and receiving data and handling acknowledgements
// by both players. Here's a typical pattern:
//
//   while(1)
//   {
//     select
//     {
//       case nbsp_receive_msg(c, state):
//       {
//         if (nbsp_handle_msg(c, state, buffer))
//         {
//           unsigned incoming_data = nbsp_received_data(state1);
//           ...
//           if (!nbsp_send(c, state, buffer, outgoing_data))
//           {
//             // buffer overflow
//             pending_outgoing_data = outgoing_data;
//           }
//           ...
//         }
//         else
//         {
//           // ack received, the buffer has some room now
//           nbsp_send(c, state, buffer, pending_outgoing_data));
//         }
//         break;
//       }
//     }
//   }
//
// Handling the overflow as shown in the example above is, of course,
// optional. The code demonstrates that, after nbsp_handle_msg returns 0,
// there is room in the outgoing buffer for at least one word of data.
//

typedef struct
{
  unsigned msg_is_ack;
  unsigned msg_data;
  unsigned words_to_be_acknowledged;

  // output buffer
  unsigned read_index;
  unsigned write_index;
  unsigned buffer_mask;

} t_nbsp_state;

#define NBSP_CT_DATA 0x5 // smallest free application token

extern void nbsp_init(t_nbsp_state& state, unsigned buffer_size_in_words);

#pragma select handler
inline void nbsp_receive_msg(chanend c, t_nbsp_state& state)
{
  unsigned char token;

  token = inct(c);

  if (token == NBSP_CT_DATA)
  {
    state.msg_is_ack = 0;
    state.msg_data = inuint(c);
  }
  else
  {
    state.msg_is_ack = 1;
  }
}

extern unsigned nbsp_handle_msg(chanend c, t_nbsp_state& state, unsigned(&?buffer)[]);

inline unsigned nbsp_received_data(t_nbsp_state& state)
{
  return state.msg_data;
}

extern unsigned nbsp_send(chanend c, t_nbsp_state& state, unsigned buffer[], unsigned data);
extern unsigned nbsp_pending_words_to_send(t_nbsp_state& state);
extern unsigned nbsp_sending_capacity(t_nbsp_state& state);
extern void nbsp_flush(chanend c, t_nbsp_state& state, unsigned buffer[]);

extern void nbsp_handle_outgoing_traffic(
  chanend c,
  t_nbsp_state& state,
  unsigned buffer[],
  unsigned available_tens_of_ns);

//-----------------------------------------------------------------------------------------
// Protocol variant UDDW = unidirectional, double word
// - sends two words at once, no tokens in forward direction
// - significantly faster (> 4...8 times compared to the unidirectional NBSP case)
// - essentially implements a streaming channel, only few allowed cross-tile!!!!
// - sender and receiver cannot be exchanged
// - receiver needs no state, sender uses normal nbsp state
// - cannot be mixed with normal nbsp on the same channel/state/buffer
// - the functions nbsp_init, nbsp_pending_words_to_send and nbsp_sending_capacity
//   can be used for both normal nbsp and for the uddw variant
// - nbsp_uddw_handle_ack replaces nbsp_receive_msg and nbsp_handle_msg on the sender side
// - nbsp_uddw_receive replaces nbsp_receive_msg, nbsp_handle_msg and nbsp_received_data
//   on the receiver side

inline unsigned nbsp_uddw_send(chanend c, t_nbsp_state& state, unsigned buffer[], unsigned data1, unsigned data2)
{
  if (state.words_to_be_acknowledged == 0)
  {
    // buffer must be empty, we can immediately send, no need for buffering
    outuint(c, data1);
    outuint(c, data2);
    state.words_to_be_acknowledged = 2;
    return 1;
  }
  else
  {
#if CHECK_FOR_PROGRAMMING_ERRORS
    if (state.buffer_mask == 0xFFFFFFFF)
    {
      printf("nudp error: nudp_uddw_send needs nonzero buffer size\n");
    }
#endif
    // busy sending, must buffer the data
    unsigned next_write_index = (state.write_index + 2) & state.buffer_mask;

    if (next_write_index != state.read_index)
    {
      buffer[state.write_index]   = data1;
      buffer[state.write_index+1] = data2;
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

#pragma select handler
inline void nbsp_uddw_handle_ack(chanend c, t_nbsp_state& state, unsigned buffer[])
{
  unsigned char token;

  token = inct(c);

#if CHECK_FOR_PROGRAMMING_ERRORS
  if (state.words_to_be_acknowledged == 0)
  {
    printf("nbsp error: unexpected ack\n");
  }
#endif

  if (state.read_index != state.write_index)
  {
    // there is more data to send
    outuint(c, buffer[state.read_index]);
    outuint(c, buffer[state.read_index + 1]);
    state.read_index = (state.read_index + 2) & state.buffer_mask;
  }
  else
  {
    state.words_to_be_acknowledged = 0;
  }
}

#pragma select handler
inline void nbsp_uddw_receive(chanend c, unsigned& data1, unsigned& data2)
{
  data1 = inuint(c);
  data2 = inuint(c);
  outct(c, XS1_CT_END);
}

extern void nbsp_uddw_flush(chanend c, t_nbsp_state& state, unsigned buffer[]);

#endif
