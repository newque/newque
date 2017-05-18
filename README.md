# Newque

> Fast, configurable message broker that saves you time and rids datastore headaches.

## Table of Contents

- [Introduction](#introduction)
  - [Basics](#basics)
  - [Newque Overview](#newque-overview)
  - [Key Benefits](#key-benefits)
  - [Common Use Case](#common-use-case)
- [Getting Started](#getting-started)
- [Integrations](#integrations)
- [Examples](#examples)
  - [Pubsub](#pubsub)
  - [FIFO](#fifo)
- [Directory Structure](#directory-structure)
- [Concepts](#concepts)
- [Logging](#logging)
- [JSON Configuration](#json-configuration)
- [Roadmap](#roadmap)
- [Contributing](#contributing)

## Introduction

### Basics

A message broker acts as a service in between networked applications, devices, datastores, etc. It can accept client applications' requests to return aggregate data from your backend servers, or itself acting as a collector. Message brokers offset developer workload and application complexity by handling several things, including:

- Collecting data
- Log aggregation
- Message parsing
- Message validation
- Request batching
- One-to-many routing (pubsub)
- Producer-consumer routing
- Proxying
- Logging

### Newque Overview

Newque - pronounced `nuke` - is a fast, declarative message broker. It can be used for common operations listed above and more. With Newque, you can:

1. Design your architecture using common patterns
2. Define it into JSON config files
3. Let Newque handle all your message needs
4. Develop and iterate faster instead of reinventing the wheel

Newque is configured with JSON files that are loaded on startup. The format of those JSON files is documented [below](https://github.com/newque/newque#configuration-files).

Newque is built around the concept of Listeners and Channels (sometimes known as "topics"). Each Channel can be accessed from zero or more Listeners. Listeners expose a protocol ([HTTP](https://github.com/newque/newque#http) or [ZMQ](https://github.com/newque/newque#zmq)) over a port. Both protocols have pros and cons. Each Channel has a Backend where messages are sent before they can be read. Messages are binary blobs; it is possible to send anything from UTF-8 text to images, JSON, compressed video, etc.

### Key Benefits

Using Newque can afford you:

- **Peace of mind**: you no longer have to ask yourself worrisome questions such as: 'What happens if one of my data processing servers goes down?'
- **Fast architecture prototyping**: it takes seconds to change the entire flow of data in your system to try different architectures. Avoid having to reinvent the wheel, or writing complicated and error-prone code to move data around.
- **Time**: queue management over failed instances, pending queues, etc require hours of development and testing. Newque handles it all.
- **Fast application performance**

### Common Use Case

Imagine clients (producers) recording events in an application. In this scenario, events happen continuously and the producers stream those single messages to Newque on a Channel (let's call it "Main") using the local disk as its Backend. This log allows the user to replay events later by Reading messages from that Backend.

The user also configured Newque to Forward messages received on the Main Channel to another Channel using ElasticSearch as its Backend (let's call that Channel "Indexer"). Indexer is not directly exposed on a Listener. The user, aware of the high overhead of HTTP requests to ElasticSearch, configured the Indexer Channel to use Batching (for example, with: size = 1000, time = 2 seconds). Therefore Newque will only make a request to ES once at least 1000 messages have been received or once 2 seconds have elapsed since the last request was made.

In this imaginary scenario, the user also needs to Forward the messages to a pool of clients (consumers) that will process them. There are multiple Backend choices available to accomplish this task: `httpproxy`, `pubsub` or `fifo`.

The user then uses the Newque high level library (driver) for the language of their choice. By not having to write all the code to route data to all these services themselves, the user can focus on what really matters: the business logic. By relying on a battle-tested platform such as Newque, they avoid reinventing the wheel with all the debugging and performance optimizations it involves.

The main operations are:

- Writing to a Channel's Backend
- Reading from a Channel's Backend
- Streaming from a Channel's Backend
- Counting the number of messages in a Channel's Backend
- Deleting all data from a Channel's Backend
- Checking the Health of a Channel's Backend
- Checking the Health of the whole system

The current Backend options are:

- `memory`: Use the local RAM to store messages.
- `disk`: Use the local disk to store messages.
- `httpproxy`: Proxy messages to a remote HTTP or another Newque server.
- `elasticsearch`: Write to ES. Messages must be valid JSON, for obvious reasons.
- `pubsub`: Broadcast to a ZMQ pubsub address. Publisher-Subscriber. (1-to-many, no ack)
- `fifo`: Send to a ZMQ FIFO address. Producer-Consumer. (1-to-1, with ack)
- `none`: Does nothing besides Forwarding to other Channels, if applicable
- ...more coming soon (Redis and PostgreSQL)

## Getting Started

To set up and run Newque:

1. Download the latest release from https://github.com/newque/newque/releases/latest and unzip it to a `path/`
1. Edit the configuration files in `path/conf/` to your needs (see [JSON Configuration](#json-configuration))
1. Run `path/newque`

## Integrations

- Disk
- ElasticSearch
- ZMQ
- Redis (coming soon)
- PostgreSQL (coming soon)

## Examples

### Pubsub

To receive messages on a `pubsub` backend, open a ZMQ socket in `sub` mode and `connect` to the Channel using the ZMQ address `tcp://PubsubChannelHost:PubsubChannelPort` and finally `subscribe` to all messages.

Newque will be sending data in the following format: [`Input`, message1, message2, etc].

A full example is available [here](https://github.com/newque/newque/blob/dd2174166a21030a66133b75904c7d40bb5898fd/test/examples/pubsub.js).

### FIFO

To receive messages on a `fifo` backend, open a ZMQ socket in `dealer` mode and `connect` to the Channel using the ZMQ address `tcp://FifoChannelHost:FifoChannelPort`.

Newque will be sending data in the following format: [`UID`, `Input`, message1, message2, etc].

`fifo` requires an Acknowledgement or else the client making a request to Newque will receive a timeout error. Using the same socket, send [`UID`, `Output`] back to Newque, where `UID` is the exact same string/buffer that was sent by Newque.

A full example is available [here](https://github.com/newque/newque/blob/dd2174166a21030a66133b75904c7d40bb5898fd/test/examples/fifo.js).

## Directory structure

```
newque/
├── conf/
│   ├── channels/
│   │   └── mychannel.json
│   ├── jsonschemas/
│   │   └── myschema.json
│   ├── scripts/
│   │   └── myscript.lua
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
- `conf/` contains the `newque.json` file and folders for the channel settings and scripts.
- `data/` is created when starting Newque and contains data generated during operation. Do not modify.
- `logs/` is created when starting Newque and contains the output and error logs.
- `lib/` contains the libraries needed to run Newque, it must be located in the same folder as the `newque` executable. Do not modify.

## Concepts

__IDs__

Each message has a unique ID and Newque will generate IDs when they are not provided by the client. If a message with the same ID already exists in the Backend it won't be written, therefore it is possible to retry messages when network errors occur. Obviously in the case of the `httpproxy`, `pubsub` and `fifo` Backends, it is up to the upstream server to implement this behavior if they wish to.

__Atomics__

When Writing a batch of messages, they can be flagged as `atomic`. They will be treated as one. They'll have a combined size of `1`, and all be written and read at once.

__Raw__

A Channel can enable the option `raw`. Atomics don't exist in this mode. Performance is marginally better for all non-atomic messages. Messages are passed as-is to the Backend, which can be useful if your `fifo`, `pubsub` or `httpproxy` remote servers need to be able to make sense of those messages. The ElasticSearch backend requires this option to be enabled.

__JSON Schema Validation__

It's possible to offload all of your JSON validation to Newque. Each channel can specify one [JSON Schema](http://json-schema.org/). Every message on that channel must successfully validate with the schema before it is sent to the channel's backend. If many messages are sent in the same call, any failure will cause the whole call to be rejected with an error.

By default, JSON Schema validations happen in the main thread to avoid excessive context switching, but calls with 10 or more messages will be validated in a background thread. This value (`10`) is configurable. See [the JSON Schema Validation object format](#json-schema-validation-object).

Note: JSON Schema files are checked on startup to ensure that they don't themselves contain errors. Newque won't start if any JSON Schema contains errors.

__Lua Scripting__

Newque offers Lua scripting. Scripts are invoked *after JSON Schema Validation, but before Batching*. A channel can have more than 1 script. They are invoked in order: the original messages are passed to the first script, then the output is passed to the second script, and so on. The output of the final script is then passed to the Batcher (if applicable) or to the channel's backend.

Scripts are simple Lua files that *must return a function that takes 2 arrays of strings and returns 2 arrays of strings*. [Here](https://github.com/newque/newque/blob/master/conf/scripts/to_uppercase.lua) is an example of a script that upper cases every message. The number of messages and the IDs must always match, but it is possible to insert or drop messages and IDs.

Each channel has its own Lua sandbox. A global variable created in a script on one channel is accessible in other scripts and in subsequent invokations. This is on purpose, it makes it possible for the user to cache values or even keep (e.g.) database connections open! However, it means that only one script per channel can be executing at any time. This restriction also ensures that the ordering of messages isn't altered due to one script invokation taking a longer time the next one. In other words, this access lock on each channel's Lua sandbox prevents race conditions.

The Lua sandboxes do not run in the main thread. It's safe to execute blocking operations, such as I/O (HTTP calls, reading files, etc.) or heavy CPU-bound processing.

Calling `error({location = "some string", message = "some other string"})` will return a formatted error message to the user. This is helpful when Lua scripts are used to do custom validation on messages.

Calling `error()` with any value other than an object having the keys `location` and `message` will be considered an "unexpected error". Strings or Numbers passed to `error()` will be logged in the Newque logs and a generic error message will be returned to the user.

From a script, it's possible to `require()` other Lua scripts located in the `conf/scripts/` directory.

Note: Lua scripts are compiled on startup and Newque won't start if any Lua script contains syntax errors.

__Batching__

Batching is an easy way to improve your application's performance. When batching is enabled on a channel, all incoming messages are added to a queue instead of being immediately sent to the channel's backend.

Batches are flushed to the backend when either one of 2 conditions are met:
- the batch size reaches `maxSize`
- the batch has not been flushed in the last `maxTime` milliseconds

Note: Setting `maxSize` to `1` will split all incoming messages into their own batch. For example, a user sending 3 messages in one call will create 3 batches.

## Logging

Verbosity is configurable using the `logLevel` settings in `newque.json`.

There are six levels, from the most to the least verbose, they are: `debug`, `info`, `notice`, `warning`, `error` and `fatal`.

The recommended level for production usage is `info`.

Levels `debug`, `info` and `notice` are written to STDOUT and `./logs/out.log`.

Levels `warning`, `error` and `fatal` are written to STDERR and `./logs/err.log`.

**Note:** If the `NEWQUE_ENV` environment variable is set, it'll be used in the log format.

## JSON Configuration

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
| `jsonValidation` | Object | No | | Settings related to JSON Schema Validation. See [JSON Schema Validation Object](#json-schema-validation-object). |
| `scripting` | Object | No | | Settings related to Lua Scripting. See [Lua Scripting Object](#lua-scripting-object). |
| `batching` | Object | No | | Settings related to batching writes. Generally results in large performance gains. See [Batching Object](#batching-object). |

__Batching Object__

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `maxTime` | Double | Yes | | How long can messages linger in the queue before they have to be written to the Backend. In milliseconds. |
| `maxSize` | Integer | Yes | | Maximum size the queue can reach before they have to be written to the Backend. |

__JSON Schema Validation Object__

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `schemaName` | String | Yes | | The name of the file in `/conf/jsonschemas` that contains the JSON Schema, e.g. `myschema.json`. |
| `parallelismThreshold` | Integer | No | `10` | The smallest numbest of messages in a call to make Newque execute the JSON Schema validation over all those calls in a separate thread. A value of `1` means Newque will never use the main thread for JSON Schema validations. |

__Lua Scripting Object__

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `mappers` | Array of strings | Yes | | A list of all the scripts to execute, in order. Those files must be located in `/conf/scripts`. |

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

## Roadmap

Planned features:

- Redis integration
- PostgreSQL integration

## Contributing

All contributions are welcome. Please start a discussion by opening an issue or continuing the conversation in an existing issue. If you wish to contribute to the source, great! Instructions to compile Newque is in [DEVELOPMENT.md](DEVELOPMENT.md). **If you plan on developing a feature or fix**, please discuss in an issue first. Doing so may help avoid having a rejected pull request, saving you time.
