# Newque

## Overview

Newque is a fast, declarative message broker.

It can be used for log aggregation, message passing, request batching, pubsub, proxying, routing, optimizing ElasticSearch ingestion rates, and more.

It is entirely configured through JSON files that are loaded on startup. The format of those JSON files is documented below.

Newque is built around the concept of Listeners and Channels. Each channel is registered on a number of Listeners. Each channel has a Backend where messages are stored before they can be read. Messages are treated as binary blobs, they don't have to (but can) be UTF-8.

Each message has a unique ID, Newque will generate IDs when they are not provided. If a message with the same ID already exists it won't be added, therefore it is safe to retry messages after a network error, for example.

The current Backend options are:

- Memory
- Disk
- Remote HTTP server
- ElasticSearch
- ...more coming soon (Redis)

The main operations are:

- Writing to a Channel
- Reading from Channel
- Streaming from Channel
- Counting the size of a Channel's Backend
- Deleting all data in a Channel's Backend
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
│   ├── channels/
│   └── out.log
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
| `backlog` | Integer | No | `20` | The `backlog` argument for the `listen(2)` syscall. |

__ZMQ Settings object__

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `concurrency` | Integer | No | `20` | Number of requests that can be processed concurrently. |
| `receiveHighWaterMark` | Integer | No | `5000` | Number of inbound messages ZMQ will keep in buffer until they can be processed. |
| `sendHighWaterMark` | Integer | No | `5000` | Number of outbound messages ZMQ will keep in buffer for slow or disconnected clients. |

### Channel configuration files

These files must be located in `conf/channels/` from the location of the `newque` executable. Each file name must end with the `.json` extension. The name of the file (without the extension) will be the name of the channel.

__Example__
```json
{
  "listeners": ["http8000", "zmq8005"],
  "backend": "disk",
  "acknowledgement": "saved",
  "readSettings": {
    "onlyOnce": true
  },
  "writeSettings": {
    "copyToChannels": ["sinkChannel"]
  },
  "raw": true,
  "emptiable": true
}

```

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `listeners` | Array of strings | Yes | | The name of all the Listeners this Channel will be available from. |
| `backend` | String | Yes | | Which type of Backend. One of `memory`, `disk`, `http` or `elasticsearch`. |
| `backendSettings` | Object | No | | The right Settings object for the `backend` value. |
| `emtiable` | Boolean | Yes | | Whether the Delete operation can be used on this Channel. |
| `raw` | Boolean | No | `false` | Whether the messages should be wrapped when writing to the Backend. |
| `readSettings` | Object or Null | Yes | | Settings related to Reading from this Channel, or `null` to disable all Reading. |
| `writeSettings` | Object or Null | Yes | | Settings related to Writing to this Channel, or `null` to disable all Writing. |
| `separator` | String | No | `\n` | String that acts as a separator between messages for `httpFormat`: `plaintext`. |
| `averageSize` | Integer | No | `256` | Average size (in bytes) of incoming (Write) HTTP bodies when `httpFormat`: `plaintext`. |
| `maxRead` | Integer | No | `1000` | How messages can be returned in a single Read operation. Includes Streaming.  |
| `averageRead` | Integer | No | `32` | Average number of messages returned per Read operation. Includes Streaming. |

__`memory` `backendSettings` Object__

The `memory` Backend does not have a `backendSettings` object.

__`disk` `backendSettings` Object__

The `disk` Backend does not have a `backendSettings` object.

__`http` `backendSettings` Object__

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `baseUrls` | Array of strings | Yes | | Base URLs to use for the remote HTTP server(s). |
| `baseHeaders` | Array of Objects | Yes | | Headers to add to every request to the remote server. |
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
| `index` | String | Yes | | The ES index name to use as a Backend. |
| `type` | String | Yes | | The ES type name to use as a Backend. |

__Read Settings Object__

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `httpFormat` | String | No | `json` | Format that the Channel uses to send back read results. One of `plaintext` or `json`. |
| `streamSliceSize` | Integer | No | `500` | How many messages return per 'slice' when streaming. |
| `onlyOnce` | Boolean | Yes | | Whether to automatically delete messages as soon as they've been read. |

__Write Settings Object__

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `httpFormat` | String | No | `json` | Format that the Channel accepts for writes. One of `plaintext` or `json`. |
| `acknowledgement` | String | No | `saved` | Whether to wait for the Write operation to be acknowledged before returning the results. One of `saved` or `instant`. |
| `copyToChannels` | Array of strings | No | | List of Channel names where the messages must also be written after they've successfully been written to the Channel. |
| `batching` | Object | No | | Settings related to batching writes. Generally results in large performance gains. |

__Batching Object__

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `maxTime` | Double | Yes | | How long can messages linger in the queue before they have to be written to the Backend. In milliseconds. |
| `maxSize` | Integer | Yes | | Maximum size the queue can reach before they have to be written to the Backend. |

## Concepts

__Atomics__

When Writing a batch of messages, they can be flagged as `atomic`. They will be treated as one. They'll have a combined size of `1`, and all be written and/or read at once.

__Raw__

A Channel can enable the option `raw`. Atomics don't exist in this mode. Performance is marginally better for all non-atomic messages. The ElasticSearch backend requires this option to be enabled.


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

Then open a ZMQ socket in `dealer` mode and `connect` to a Newque ZMQ Listener.

A complete Node.js example is available [here](https://github.com/SGrondin/newque/blob/master/test/zmq.js).

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
