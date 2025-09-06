# BChat

## 개요

본 프로젝트는 Bluetooth Mesh를 통해 Peer 간 메시지를 전달할 수 있는 간단한 메시징 애플리케이션입니다.

[**Bitchat**](https://github.com/permissionlesstech/bitchat) 아이디어를 기반으로, 현재는 닉네임 교환, BLE 기반 메시지 전송, 대량 메시지의 압축 및 분할 처리까지 지원합니다.

## BitchatPacket 바이너리 구조

```
┌──────────────────────────┬───────────────┬────────────────┬──────────────┐
│ 구분                      │ Offset (Byte) │ 필드 (Field)    │ 크기 (Bytes)  │
├──────────────────────────┼───────────────┼────────────────┼──────────────┤
│ 고정 헤더(22 Bytes)        │ 0             │ version        │ 1            │
│                          │ 1             │ type           │ 1            │
│                          │ 2             │ ttl            │ 1            │
│                          │ 3-10          │ timestamp      │ 8            │
│                          │ 11            │ flags          │ 1            │
│                          │ 12-13         │ payload_length │ 2            │
│                          │ 14-21         │ senderID       │ 8            │
│ 가변 헤더(8 Bytes)         │ 22-29         │ recipientID    │ 8            │
│ 페이로드                   │ 30-           │ Payload        │ 가변          │
└──────────────────────────┴───────────────┴────────────────┴──────────────┘
```

필드 설명:

- Version : 프로토콜 버전 (v1)
- Type : 메시지 타입 (1=announce, 2=message, 3=leave, 4=fragment)
- TTL : Time to live (default: 8)
- Timestamp : 생성 시각
- Flags : Bit 0=Recipient present, Bit 1=Compressed
- Sender ID : Peer identifier
- Recipient : Optional 8-byte recipient (nil for broadcast)

## 분할 패킷(MessageType=4)의 페이로드 구조

BitchatPacket의 type이 4(fragment)일 때의 Payload 내부 구조

```
분할 페이로드 구조
┌────────────────┬──────────────┐
│ 필드 (Field)    │ 크기 (Bytes)  │
├────────────────┼──────────────┤
│ Fragment ID    │ 8            │
│ Fragment Index │ 2            │
│ Fragment Total │ 2            │
│ Original Type  │ 1            │
│ Packet Chunk   │ 가변          │
└────────────────┴──────────────┘
```

필드 설명:

- Fragment ID: 분할된 메시지 그룹 전체를 식별하는 고유 ID
- Fragment Index: 현재 조각의 순서
- Fragment Total: 전체 조각의 개수
- Original Type: 분할되기 전 원본 패킷의 타입
- Packet Chunk: 원본 패킷의 바이너리 데이터 조각(단순 텍스트가 아닌, 원본 패킷의 헤더+페이로드가 포함된 바이너리 그 자체의 일부)

## 공지 패킷(MessageType=1)의 페이로드 구조

BitchatPacket의 type이 1(announce)일 때의 Payload는 아래 두 TLV(Type-Length-Value) 구조가 순서대로 합쳐진 형태

```
TLV 기본 구조
┌────────┬──────────────┐
│ 필드    │ 크기 (Bytes)  │
├────────┼──────────────┤
│ Type   │ 1            │
│ Length │ 1            │
│ Value  │ 가변          │
└────────┴──────────────┘

공지 페이로드 구조
┌──────────────┬──────────────┐
│ 필드 (Field)  │ 크기 (Bytes)  │
├──────────────┼──────────────┤
│ Nickname TLV │ 2 + α        │
│ PeerID TLV   │ 2 + β        │
└──────────────┴──────────────┘
```

필드 설명:

- Nickname TLV
  - Type: 닉네임 타입을 의미하며, 항상 0x01
  - Length: 뒤따라오는 닉네임 문자열의 길이
  - Value: 닉네임 (UTF-8 문자열)
- PeerID TLV
  - Type: PeerID 타입을 의미하며, 항상 0x02
  - Length: 뒤따라오는 PeerID 문자열의 길이
  - Value: PeerID (UTF-8 문자열)

## TODO

- [x] Message based on BLE
- [x] Packet Implementation(Broadcasting - BitchatPacket, AnnouncementPacket)
- [x] Fragmentation & Compression
- [x] Deduplication
- [x] Active Scanning
- [ ] Handshake with Encryption
- [ ] DM
- [ ] Nostr
