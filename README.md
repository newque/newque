# newque

## Overview

Newque is a fast, declarative message broker.

It can be used for log aggregation, message passing, request batching, pubsub, proxying, routing, optimizing ElasticSearch ingestion rates, and more.

It is entirely configured through JSON files that are loaded on startup. The format of those JSON files is documented below.

Newque is built around the concept of Listeners and Channels. Each channel listens to a number of Listeners. Each channel has a Backend where messages are stored before they can be read. The current Backend options are:

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
| `averageSize` | Integer | No | `256` | Average size (in bytes) of HTTP bodies for `httpFormat`: `plaintext`. |
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
| `appendChannelName` | Boolean | Yes | | Append the channel name to the URL path. |
| `remoteInputFormat` | String | No | `json` | Format that the remote server accepts for writes. One of `plaintext` or `json`. |
| `remoteOutputFormat` | String | No | `json` | Format that the remote server uses to send read results. One of `plaintext` or `json`. |

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
| `maxTime` | Double | Yes | | How long can messages linger in the queue before they have to be written to the Backend. In seconds. |
| `maxSize` | Integer | Yes | | Maximum size the queue can reach before they have to be written to the Backend. |
