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
- `lib/` contains the libraries needed to run Newque, it must be located in the same folder as the `newque` executable

## Concepts

__Atomics__

When Writing a batch of messages, they can be flagged as `atomic`. They will be treated as one. They'll have a combined size of `1`, and all be written and/or read at once.

__Raw__

A Channel can enable the option `raw`. Atomics don't exist in this mode. Performance is marginally better for all non-atomic messages. The ElasticSearch backend requires this option to be enabled.

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
| `separator` | String | No | `\n` | String that acts as a separator between messages for `httpFormat`: `plaintext`. |
| `averageSize` | Integer | No | `256` | Average size (in bytes) of incoming (Write) HTTP bodies when `httpFormat`: `plaintext`. |
| `maxRead` | Integer | No | `1000` | How messages can be returned in a single Read operation. Includes Streaming.  |
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

Interacting with Newque over HTTP is the most flexible way. Its performance is adequate as long as calls are infrequent enough. If you find yourself in a position where you need to make many small HTTP calls at a high rate, consider using ZMQ.

### Writing

The Writing `httpFormat` is `json` by default.

#### Request when the `httpFormat` is `json`

Endpoint: `http://hostname:port/v1/mychannel`

Method: `POST`

Headers: N/A

Body: Example:
```json
{
  "atomic": false,
  "messages": ["message1", "message2", "message3"],
  "ids": ["id1", "id2", "id3"]
}
```

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `atomic` | Boolean | No | `false` | Must the messages be treated as one? |
| `messages` | Array of strings | Yes | | The actual messages. |
| `ids` | Array of strings | No | | The IDs of the messages. Lengths must match. |

#### Request when the `httpFormat` is `plaintext`

Endpoint: `http://hostname:port/v1/mychannel`

Method: `POST`

Headers:
- (required) `newque-mode`. One of:
  - `single`: The entire body is a single message.
  - `multiple`: The body is multiple messages, separated by `separator`. Therefore a message cannot contain the string `separator`.
  - `atomic`: Same as `multiple`, but all the messages will be treated as one. They'll have a combined size of `1`, and all be written and/or read at once.
- (optional) `newque-msg-id`. A list of comma-separated unique IDs for the messages. The number of IDs must match the number of messages. If this header is missing, Newque will generate new unique IDs.

Body: See the `newque-mode` header. Unless the Mode is `single`, the body will consist in a list of messages separated by `separator`. Example: `message1__message2__message3` will result in 3 messages if the Mode is `multiple` and the Channel's `separator` is `__`.

#### Response for both `json` and `plaintext`

Status:
- `201`: Messages were saved successfully.
- `202`: The request was received, but `acknowledgement` is set to `instant`, therefore we don't know if the operation succeeded.
- `4xx`: Client error
- `5xx`: Server error

Headers:
- `content-type: application/json`

Body:

A JSON object. Example:
```json
{
  "code": 201,
  "errors": [],
  "saved": 3
}
```

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `code` | Integer | Yes | | The HTTP status code. |
| `errors` | Array of strings | Yes | | A list of errors. |
| `saved` | Array of strings | No | | How many messages were saved successfully. |

### Read

The Reading `httpFormat` is `json` by default. Everything is identical between both formats, except for the response body.

#### Request

Endpoint: `http://hostname:port/v1/mychannel`

Method: `GET`

Headers:
- (required) `newque-mode`. One of:
  - `one`. Returns a single message.
  - `many X` where `X` is an integer. Returns up to `X` messages.
  - `after_id X` where `X` is a string. Returns as many messages as possible that were received after that ID.
  - `after_ts X` where `X` is a timestamp in nanoseconds. Returns as many messages as possible that were received after that timestamp.
- (optional) `newque-read-max`. An integer to set an upper bound to the number of returned messages. Note: Channels also have a `maxRead` setting.

Body: N/A

#### Response

Status:
- `200`: Messages have been retrieved successfully.
- `4xx`: Client error
- `5xx`: Server error

Headers:
- `content-type: X` where `X` is `application/json` (when format is `json`) or `application/octet-stream` (when format is `plaintext`).
- `newque-response-length: X` where `X` is the number of messages returned.
- (if backend supports it) `newque-response-last-id: X` where `X` is the ID of the last message returned.
- (if backend supports it) `newque-response-last-ts: X` where `X` is the timestamp (in nanoseconds) of the last message returned.

**Body (`json` format)**:

A JSON object. Example:
```json
{
  "code": 200,
  "errors": [],
  "messages": ["message1", "message2", "message3"]
}
```

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `code` | Integer | Yes | | The HTTP status code. |
| `errors` | Array of strings | Yes | | A list of errors. |
| `messages` | Array of strings | Yes | | A list of messages. |

**Body (`plaintext` format)**: All the messages concatenated by the `separator` string.

### Read (Streaming)

This is a special case. Adding the `Transfer-Encoding: Chunked` header to a Read call will make Newque stream messages back as fast as possible in `plaintext` format (no matter the format configured on the Channel). This can be useful when reading a very large number of messages at once because they do not have to be buffered up in memory before being returned.

### Count

#### Request

Endpoint: `http://hostname:port/v1/mychannel/count`

Method: `GET`

Headers: N/A

Body: N/A

#### Response

Status:
- `200`: Success
- `4xx`: Client error
- `5xx`: Server error

Headers:
- `content-type: application/json`

Body:

A JSON object. Example:
```json
{
  "code": 200,
  "errors": [],
  "count": 3
}
```

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `code` | Integer | Yes | | The HTTP status code. |
| `errors` | Array of strings | Yes | | A list of errors. |
| `count` | Integer | No | | How many messages are present in the backend. |

### Delete

#### Request

Endpoint: `http://hostname:port/v1/mychannel`

Method: `DELETE`

Headers: N/A

Body: N/A

#### Response

Status:
- `200`: Success
- `4xx`: Client error
- `5xx`: Server error

Headers:
- `content-type: application/json`

Body:

A JSON object. Example:
```json
{
  "code": 200,
  "errors": []
}
```

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `code` | Integer | Yes | | The HTTP status code. |
| `errors` | Array of strings | Yes | | A list of errors. |

### Health

It's possible to check the health for a single channel or the entire system.

#### Request

Endpoint: `http://hostname:port/v1/mychannel/health` **or** `http://hostname:port/v1/health`

Method: `GET`

Headers: N/A

Body: N/A

#### Response

Status:
- `200`: Success
- `4xx`: Client error
- `5xx`: Server error

Headers:
- `content-type: application/json`

Body:

A JSON object. Example:
```json
{
  "code": 200,
  "errors": []
}
```

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `code` | Integer | Yes | | The HTTP status code. |
| `errors` | Array of strings | Yes | | A list of errors. |

## ZMQ

ZMQ is (much) faster and easier to use, once the boilerplate is in place.

**All the formats are already defined in [this file](https://github.com/SGrondin/newque/blob/master/protobuf/zmq_obj.proto)**

So go ahead and use your language's code generator for `.proto` files. Send `Input` Protobuf objects as defined in [the spec](https://github.com/SGrondin/newque/blob/master/protobuf/zmq_obj.proto) and Newque will return `Output` objects.

Then open a ZMQ socket in `dealer` mode and `connect` to a Newque ZMQ Listener using the address `tcp://ListenerHost:ListenerPort`.

A complete Node.js example is available [here](https://github.com/SGrondin/newque/blob/dd2174166a21030a66133b75904c7d40bb5898fd/test/examples/zmq.js).

### Basic operations

#### Write

Send [`UID`, `Input`, message1, message2, etc] on the ZMQ socket.

`UID` must be a unique string. `Input` is a [Protobuf object](https://github.com/SGrondin/newque/blob/master/protobuf/zmq_obj.proto) with the `action` field set to `Write_Input`.

Newque will return [`UID`, `Output`].

`UID` will be the exact same string that was sent with the request. This is so that you can associate responses with their requests. `Output` is a [Protobuf object](https://github.com/SGrondin/newque/blob/master/protobuf/zmq_obj.proto) with the `action` field set to `Write_Output` or `Error_Output`.

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

#### Pubsub

To receive messages from a `pubsub` backend, open a ZMQ socket in `sub` mode and `connect` to the Channel using the address `tcp://PubsubChannelHost:PubsubChannelPort` and finally subscribe to all messages.

Newque will be sending data in the following format: [`Input`, message1, message2, etc].

A full example is available [here](https://github.com/SGrondin/newque/blob/dd2174166a21030a66133b75904c7d40bb5898fd/test/examples/pubsub.js).

#### FIFO

To receive messages from a `fifo` backend, open a ZMQ socket in `dealer` mode and `connect` to the Channel using the address `tcp://FifoChannelHost:FifoChannelPort`.

Newque will be sending data in the following format: [`UID`, `Input`].

`fifo` requires an Acknowledgement or else the client making a request to Newque will receive a timeout error. Using the same socket, send [`UID`, `Output`] back to Newque.

A full example is available [here](https://github.com/SGrondin/newque/blob/dd2174166a21030a66133b75904c7d40bb5898fd/test/examples/fifo.js).
