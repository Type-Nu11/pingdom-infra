# Pingdom Infrastructure & Gateway

![Pingdom Gateway Architecture](https://github.com/user-attachments/assets/945c1072-21d6-45c6-938d-21aabaea3beb)

## Overview

이 저장소는 Pingdom 프로젝트의 Infrastructure 및 Gateway 영역을 관리합니다.

외부 요청은 다음 계층을 통해 내부 Backend Server로 전달됩니다.

```text
TLS Proxy
    ↓
HAProxy
    ↓
OpenResty Gateway
 ├─ Web Proxy
 ├─ App Proxy
 ├─ Lua: 요청 흐름·라우팅 제어
 ├─ Zig: 저수준 악성 요청 탐지
 └─ Rust: JWT·HMAC 인증 검증
    ↓
Backend Server
```

OpenResty는 클라이언트 요청의 라우팅과 정책 적용을 담당하며, Zig와 Rust 네이티브 모듈을 FFI로 연결해 요청 보안 검증을 수행합니다.

## Project Status

현재 개발 및 통합 테스트 단계입니다.

Docker 기반 Gateway 실행 환경과 Web/App 요청 흐름을 구성했으며, Rust FFI 인증 검증과 Zig 기반 요청 방어 로직을 검증하고 있습니다.

| Item | Status |
|---|---|
| Development | `In Development` |
| Release | `Pre-release` |
| Stability | `Integration Testing` |

## Repository Role

| Item | Description |
|---|---|
| Type | `Infrastructure` |
| Responsibility | Pingdom 서비스 진입점 및 Reverse Proxy Gateway 관리 |
| Primary Output | OpenResty Gateway 실행 환경 |
| Target | Client Application, Backend Server 및 내부 서비스 |

## Scope

### Included

- TLS Proxy 뒤의 Gateway 계층 구성
- HAProxy 기반 글로벌 트래픽 제어
- OpenResty Web/App Proxy 구성
- Lua 기반 요청 수집·라우팅·응답 처리
- Rust FFI 기반 JWT·HMAC 검증
- Zig FFI 기반 악성 요청 탐지
- URI·Method·User-Agent 구조 검사
- NULL byte·제어문자·CRLF 차단
- Path Traversal·Double Encoding 탐지
- Docker 기반 통합 실행 환경

### Not Included

- Backend Server 비즈니스 로직
- 사용자 데이터 저장 및 관리
- 서비스 도메인 기능 구현
- 데이터베이스 운영
- TLS 인증서 발급 및 외부 TLS 종료

## Key Capabilities

### Layered Gateway

TLS Proxy, HAProxy, OpenResty를 계층화하여 연결 제어, 트래픽 분산, 서비스별 정책 적용을 분리합니다.

### Web/App Proxy Separation

웹 요청과 앱 요청을 별도의 location과 Lua entrypoint에서 처리합니다.

### Lua Request Orchestration

Lua는 요청 정보를 수집하고, 인증 및 보안 모듈을 호출하며, 백엔드 전달 흐름을 제어합니다.

### Rust Security Validation

Rust는 메모리 안전성을 기반으로 다음 검증을 담당합니다.

- JWT HS512 서명 검증 (Spring 발급 규격과 일치, 다른 알고리즘은 거절)
- `JWT_SECRET_KEY`는 Spring `JWT_SECRET`과 동일한 원문 문자열을 사용합니다. Base64 디코딩하지 않습니다.
- JWT `exp` 및 `iat` 검증
- 앱 요청 HMAC 검증
- Rust shared library FFI 제공

### Zig Request Guard

Zig는 요청 초입에서 저비용 바이트 검사를 수행합니다.

- 허용 Method 검사
- URI·User-Agent 길이 제한
- NULL byte 차단
- 제어문자·CRLF 차단
- Path Traversal 탐지
- Double Encoding 탐지

## Technology

| Category | Technology |
|---|---|
| Edge Load Balancer | HAProxy |
| Gateway | OpenResty |
| Proxy Server | Nginx |
| Dynamic Layer | Lua / LuaJIT |
| Security Validation | Rust |
| Request Guard | Zig |
| FFI | LuaJIT FFI |
| Containerization | Docker / Docker Compose |

## Getting Started

### Requirements

- Docker Desktop 또는 Docker Engine
- Docker Compose
- Git

### Setup

```bash
git clone https://github.com/Type-Nu11/pingdom-infra.git
cd pingdom-infra
```

### Build

```bash
docker compose build
```

Docker 빌드 과정에서 다음 네이티브 라이브러리가 생성됩니다.

```text
libapp_validator.so
libweb_guard.so
```

### Run

```bash
docker compose up -d
```

실행 상태 확인:

```bash
docker compose ps
```

Gateway 로그 확인:

```bash
docker compose logs -f reverse-proxy
```

기본 테스트 주소:

```text
http://localhost:8081
```

## Configuration

주요 설정 파일:

```text
nginx.conf
docker-compose.yml
Dockerfile
configs/conf.d/
src/lua/
rust/validator/
zig/guard/
```

네이티브 라이브러리 경로는 다음 환경변수로 전달됩니다.

```text
RUST_VALIDATOR_LIB
WEB_GUARD_LIB
```

인증 키와 비밀 값은 저장소에 커밋하지 않습니다.

## Verification

OpenResty 설정 검사:

```bash
docker compose exec reverse-proxy openresty -t
```

정상 요청:

```bash
curl -i http://localhost:8081/
```

인증 없는 요청:

```text
401 Unauthorized
```

이중 인코딩 요청:

```bash
curl -i 'http://localhost:8081/%252e%252e'
```

유효한 JWT와 함께 실행하면:

```text
403 Forbidden
```

예상 응답 코드:

| Status | Meaning |
|---|---|
| `2xx` | 정상적으로 백엔드 전달 |
| `400` | Nginx 요청 파서 단계에서 차단 |
| `401` | JWT 인증 실패 |
| `403` | Zig 보안 정책에 의해 차단 |
| `502` | 백엔드 연결 실패 |

## Repository Structure

```text
.
├── Dockerfile
├── docker-compose.yml
├── nginx.conf
├── Cargo.toml
├── Cargo.lock
├── configs
│   └── conf.d
│       ├── app
│       ├── web
│       ├── http
│       └── shared
├── rust
│   └── validator
│       └── src
│           ├── lib.rs
│           ├── app_validator.rs
│           └── jwt_validator.rs
├── zig
│   └── guard
│       ├── build.zig
│       └── src
│           └── guard.zig
└── src
    └── lua
        ├── app_entry.lua
        ├── web_entry.lua
        ├── app_request.lua
        ├── web_request.lua
        ├── common
        ├── rust
        └── zig
```

## Related Repositories

| Repository | Relationship |
|---|---|
| `pingdom-server` | Gateway를 통해 요청을 전달받는 Backend Server |
| `pingdom-mcp` | AI 기반 데이터 처리 및 MCP 서비스 연동 |

## Architecture Principles

- HAProxy는 함대 전체의 연결과 트래픽을 제어합니다.
- OpenResty는 Web/App 요청별 정책과 라우팅을 담당합니다.
- Lua는 런타임 요청 흐름을 조정합니다.
- Zig는 빠른 저수준 요청 필터링을 담당합니다.
- Rust는 인증과 암호 검증을 담당합니다.
- 백엔드에는 검증된 요청만 전달합니다.

## License

이 프로젝트의 사용 및 배포 조건은 저장소의 `LICENSE` 파일을 따릅니다.

Part of Pingdom.
