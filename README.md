# Newque

## Overview

Newque - pronounced `nuke` - is a fast, declarative message broker.

It can be used for log aggregation, message passing, request batching, pubsub, proxying, routing, optimizing ElasticSearch ingestion rates, and more.

It is entirely configured through JSON files that are loaded on startup. The format of those JSON files is documented below.

Newque is built around the concept of Listeners and Channels. Each channel is registered on a number of Listeners. Each channel has a Backend where messages are stored before they can be read. Messages are treated as binary blobs, they don't have to (but can) be UTF-8.

Each message has a unique ID, Newque will generate IDs when they are not provided. If a message with the same ID already exists it won't be added, therefore it is safe to retry messages after a network error, for example.

The current Backend options are:

- None
- Memory
- Disk
- Proxy to a remote HTTP or Newque server
- ElasticSearch
- Publish to pubsub (1-to-many, no ack)
- Publish to a FIFO queue (1-to-1, with ack)
- ...more coming soon (Redis)

The main operations are:

- Writing to a Channel
- Reading from Channel
- Streaming from Channel
- Counting the number of messages in a Channel's Backend
- Deleting all data from a Channel's Backend
- Checking the Health of a Channel
- Checking the Health of all Channels

Every Backend, its possible use cases and the main operations are documented below.

## Directory structure

```
newque/
├── conf/
│   ├── channels/
│   │   └── mychannel.json
│   └── newque.json
├── data/
│   ├── channels/
│   │   └── mychannel.data
├── logs/
│   ├── out.log
│   └── err.log
├── lib/
│   ├── libev.so.4
│   ├── libsqlite3.so.0
│   └── libzmq.so.4
└── newque
```

__Directories__
- `conf/` contains the `newque.json` file and a folder with the settings for every channel.
- `data/` is created when starting Newque and contains data generated during operation. Do not modify.
- `logs/` is created when starting Newque and contains the output and error logs.
- `lib/` contains the libraries needed to run Newque, it must be located in the same folder as the `newque` executable

## Concepts

__Atomics__

When Writing a batch of messages, they can be flagged as `atomic`. They will be treated as one. They'll have a combined size of `1`, and all be written and/or read at once.

__Raw__

A Channel can enable the option `raw`. Atomics don't exist in this mode. Performance is marginally better for all non-atomic messages. The ElasticSearch backend requires this option to be enabled.

## Logging

Verbosity is configurable using the `logLevel` settings in `newque.json`.

There are six levels, from the most to the least verbose, they are: `debug`, `info`, `notice`, `warning`, `error` and `fatal`.

The recommended level for production usage is `info`.

Levels `debug`, `info` and `notice` are written to STDOUT and `./logs/out.log`.

Levels `warning`, `error` and `fatal` are written to STDERR and `./logs/err.log`.

**Note:** If the `NEWQUE_ENV` environment variable is set, it'll be used in the log format.

## Configuration files

### Main configuration file (`newque.json`)

This file must be located in `conf/` from the location of the `newque` executable.

__Example__
```json
{
  "logLevel": "info",
  "admin": {
    "host": "0.0.0.0",
    "port": 8001
  },
  "listeners": [
    {
      "protocol": "http",
      "name": "http8000",
      "host": "0.0.0.0",
      "port": 8000,
      "protocolSettings": {}
    },
    {
      "protocol": "zmq",
      "name": "zmq8005",
      "host": "0.0.0.0",
      "port": 8005,
      "protocolSettings": {
        "concurrency": 20
      }
    }
  ]
}
```

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `logLevel` | String | Yes | | Verbosity level. One of `debug`, `info`, `notice`, `warning`, `error` or `fatal` |
| `admin` | Object | Yes | | Admin API settings. See `Admin object`. |
| `listeners` | Array of Objects | Yes | | Newque network settings. See `Listener object`. |

__Admin object__

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `host` | String | Yes | | Address on which to listen |
| `port` | Integer | Yes | | Port to use |

__Listener object__

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `protocol` | String | Yes | | Protocol, must be `http` or `zmq` |
| `name` | String | Yes | | Unique name |
| `host` | String | Yes | | Address on which to listen |
| `port` | Integer | Yes | | Port to use |
| `protocolSettings` | Object | Yes | | Advanced network options for the protocol. See `HTTP Settings object` and `ZMQ Settings object`. |

__HTTP Settings object__

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `backlog` | Integer | No | `100` | The `backlog` argument for the `listen(2)` syscall. |

__ZMQ Settings object__

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `concurrency` | Integer | No | `20` | Number of requests that can be processed concurrently. |
| `socketSettings` | Object | No | | Low level, advanced ZMQ socket options. See `Socket Settings object`. |

__Socket Settings object__

**IMPORTANT:** Read [the docs](http://api.zeromq.org/4-0:zmq-setsockopt) before changing any defaults!
| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `ZMQ_MAXMSGSIZE` | Integer | No | `-1` | Max message size in bytes, `-1` means unlimited.  |
| `ZMQ_LINGER` | Integer | No | `60000` | How long to keep unaccepted messages after disconnection in milliseconds. |
| `ZMQ_RECONNECT_IVL` | Integer | No | `100` | Reconnection interval in milliseconds. |
| `ZMQ_RECONNECT_IVL_MAX` | Integer | No | `60000` | Max exponential backoff reconnection interval in milliseconds. |
| `ZMQ_BACKLOG` | Integer | No | `100` | The `backlog` argument for the `listen(2)` syscall. |
| `ZMQ_SNDHWM` | Integer | No | `5000` | Hard limit on the number outbound outstanding messages per connection. |
| `ZMQ_RCVHWM` | Integer | No | `5000` | Hard limit on the number inbound outstanding messages per connection. |

### Channel configuration files

These files must be located in `conf/channels/` from the location of the `newque` executable. Each file name must end with the `.json` extension. The name of the file (without the extension) will be the name of the channel.

__Example__
```json
{
  "listeners": ["http8000", "zmq8005"],
  "backend": "disk",
  "acknowledgement": "saved",
  "readSettings": {
    "onlyOnce": false
  },
  "writeSettings": {
    "forward": ["sinkChannel"]
  },
  "raw": true,
  "emptiable": true
}

```

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `listeners` | Array of strings | Yes | | The name of all the Listeners this Channel will be available from. |
| `backend` | String | Yes | | Which type of Backend. One of `none`, `memory`, `disk`, `httpproxy`, `elasticsearch`, `pubsub` or `fifo`. |
| `backendSettings` | Object | No | | The right Settings object for the `backend` value. |
| `emtiable` | Boolean | Yes | | Whether the Delete operation can be used on this Channel. |
| `raw` | Boolean | Yes | | Whether the messages should be wrapped when writing to the Backend. |
| `readSettings` | Object or Null | Yes | | Settings related to Reading from this Channel, or `null` to disable all Reading. |
| `writeSettings` | Object or Null | Yes | | Settings related to Writing to this Channel, or `null` to disable all Writing. |
| `separator` | String | No | `\n` | String that acts as a separator between messages when `httpFormat` is set to `plaintext`. |
| `averageSize` | Integer | No | `256` | Performance optimization. Average size (in bytes) of incoming (Write) HTTP bodies when `httpFormat` is set to `plaintext`. |
| `maxRead` | Integer | No | `1000` | How many messages can be returned in a single Read operation. Also affects Streaming.  |
| `averageRead` | Integer | No | `32` | Average number of messages returned per Read operation. Includes Streaming. |

__`none` `backendSettings` Object__

The `none` Backend does not have a `backendSettings` object.

__`memory` `backendSettings` Object__

The `none` Backend does not have a `backendSettings` object.

__`disk` `backendSettings` Object__

The `none` Backend does not have a `backendSettings` object.

__`httpproxy` `backendSettings` Object__

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `baseUrls` | Array of strings | Yes | | Base URLs to use for the remote HTTP server(s). |
| `baseHeaders` | Array of Objects | Yes | | Headers to add to every request to the remote server. |
| `timeout` | Number | Yes | | Number of milliseconds before calls to the remote server are cancelled with an error. |
| `appendChannelName` | Boolean | No | `false` | Append the channel name to the URL path. |
| `remoteInputFormat` | String | No | `json` | Format that the remote server accepts for writes. One of `plaintext` or `json`. |
| `remoteOutputFormat` | String | No | `json` | Format that the remote server uses to send read results. One of `plaintext` or `json`. |

Header object:
| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `key` | String | Yes | | Header name |
| `value` | String | Yes | | Header value |

__`elasticsearch` `backendSettings` Object__

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `baseUrls` | Array of strings | Yes | | Base URLs to use for the ES server(s). |
| `timeout` | Number | Yes | | Number of milliseconds before calls to the ES server are cancelled with an error. |
| `index` | String | Yes | | The ES index name to use as a Backend. |
| `type` | String | Yes | | The ES type name to use as a Backend. |

__`pubsub` `backendSettings` Object__

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `host` | String | Yes | | Address on which the messages will be broadcasted |
| `port` | Integer | Yes | | Port on which the messages will be broadcasted |
| `socketSettings` | Object | No | | Low level, advanced ZMQ socket options. See `Socket Settings object`. |

__`fifo` `backendSettings` Object__

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `host` | String | Yes | | Address on which the messages will queued up for clients to accept |
| `port` | Integer | Yes | | Port on which the messages will queued up for clients to accept |
| `timeout` | Number | Yes | | Number of milliseconds before requests are cancelled with an error. |
| `healthTimeLimit` | Number | No | `5000` | Number of milliseconds before unanswered health calls are resolved as successful. This is useful when no consumers are currently listening. |
| `socketSettings` | Object | No | | Low level, advanced ZMQ socket options. See `Socket Settings object`. |

__Read Settings Object__

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `httpFormat` | String | No | `json` | Format that the Channel uses to send back read results. One of `plaintext` or `json`. |
| `streamSliceSize` | Integer | No | `500` | How many messages return per 'slice' when streaming. |
| `onlyOnce` | Boolean | No | `false` | Whether to automatically delete messages while reading them. This only has an effect for the `memory` and `disk` backends, as they are the only backends where Newque manages storage itself. |

__Write Settings Object__

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `httpFormat` | String | No | `json` | Format that the Channel accepts for writes. One of `plaintext` or `json`. |
| `acknowledgement` | String | No | `saved` | Whether to wait for the Write operation to be acknowledged before returning the results. One of `saved` or `instant`. |
| `forward` | Array of strings | No | | List of Channel names where the messages must also be written after they've successfully been written to the Channel. |
| `batching` | Object | No | | Settings related to batching writes. Generally results in large performance gains. |

__Batching Object__

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `maxTime` | Double | Yes | | How long can messages linger in the queue before they have to be written to the Backend. In milliseconds. |
| `maxSize` | Integer | Yes | | Maximum size the queue can reach before they have to be written to the Backend. |

## HTTP

Interacting with Newque over HTTP is the most flexible way. It offers good performance, but HTTP comes with a heavy overhead per request. If you find yourself making many small HTTP calls at a high rate, consider using ZMQ instead. However, HTTP is a lot easier to load balance and is usable directly on the command line with tools such as `curl`.

An important concept to grasp is that of the `httpFormat`. Each channel has its own `httpFormat`, one for Writing (`POST`) and one for Reading (`GET`). Valid formats are `json` (default) and `plaintext`.

The formats, as well as every possible operation are defined in the [HTTP API Spec](https://newque.github.io/).

## ZMQ

ZMQ is much faster and does not suffer from the same overhead as HTTP, but being a long-lived TCP socket, it can be much harder to load balance than HTTP.

**All the formats are already defined in [the ZMQ API Spec](https://github.com/newque/newque/blob/master/specs/zmq_api.proto)**

Use your language's code generator for `.proto` files. Send `Input` Protobuf objects as defined in [the spec](https://github.com/newque/newque/blob/master/specs/zmq_api.proto) and Newque will return `Output` objects.

Then open a ZMQ socket in `dealer` mode and `connect` to a Newque ZMQ Listener using the address `tcp://ListenerHost:ListenerPort`.

A complete Node.js example is available [here](https://github.com/newque/newque/blob/dd2174166a21030a66133b75904c7d40bb5898fd/test/examples/zmq.js).

### Basic operations

#### Write

Send [`UID`, `Input`, message1, message2, etc] on the ZMQ socket.

`UID` must be a unique string. `Input` is a [Protobuf object](https://github.com/newque/newque/blob/master/specs/zmq_api.proto) with the `action` field set to `Write_Input`.

Newque will return [`UID`, `Output`].

`UID` will be the exact same string that was sent with the request. This is so that you can associate responses with their requests. `Output` is a [Protobuf object](https://github.com/newque/newque/blob/master/specs/zmq_api.proto) with the `action` field set to `Write_Output` or `Error_Output`.

#### Read

Send [`UID`, `Input`] on the ZMQ socket.

Newque will return [`UID`, `Output`, message1, message2, etc].

#### Count

Send [`UID`, `Input`] on the ZMQ socket.

Newque will return [`UID`, `Output`].

#### Delete

Send [`UID`, `Input`] on the ZMQ socket.

Newque will return [`UID`, `Output`].

#### Health

Send [`UID`, `Input`] on the ZMQ socket.

Newque will return [`UID`, `Output`].

### Backend integrations

This section describes how to accept requests from Newque and serve as a backend for a channel.

#### Pubsub

To receive messages on a `pubsub` backend, open a ZMQ socket in `sub` mode and `connect` to the Channel using the ZMQ address `tcp://PubsubChannelHost:PubsubChannelPort` and finally `subscribe` to all messages.

Newque will be sending data in the following format: [`Input`, message1, message2, etc].

A full example is available [here](https://github.com/newque/newque/blob/dd2174166a21030a66133b75904c7d40bb5898fd/test/examples/pubsub.js).

#### FIFO

To receive messages on a `fifo` backend, open a ZMQ socket in `dealer` mode and `connect` to the Channel using the ZMQ address `tcp://FifoChannelHost:FifoChannelPort`.

Newque will be sending data in the following format: [`UID`, `Input`].

`fifo` requires an Acknowledgement or else the client making a request to Newque will receive a timeout error. Using the same socket, send [`UID`, `Output`] back to Newque, where `UID` is the exact same string/buffer that was sent by Newque.

A full example is available [here](https://github.com/newque/newque/blob/dd2174166a21030a66133b75904c7d40bb5898fd/test/examples/fifo.js).
