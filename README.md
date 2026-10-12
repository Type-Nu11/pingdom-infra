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
 └─ Rust: JWT 검증 및 앱 메타데이터 유효성 검사
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
- Rust FFI 기반 JWT 및 앱 헤더 검증
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
- `X-Timestamp` freshness, `X-App-Version` 최소 버전, `X-Device-Id` UUID 검증
- `APP_MIN_VERSION`보다 낮은 앱 버전 거절 (기본값 `0.0.0`)
- 검증된 앱 헤더는 Backend로 전달합니다.
- Timestamp freshness만으로는 서명/nonce 없는 재전송 공격을 막지 못합니다.
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

### GitHub Actions Deployment

`.github/workflows/deploy-l7.yml` deploys automatically when changes reach `main`.
It can also be started manually from **Actions → Deploy L7 Proxy**, selecting a branch.
The instance checkout is cloned when absent and otherwise updated with a fast-forward-only pull.
The workflow refuses to overwrite a dirty checkout and only recreates the `reverse-proxy`
service, leaving the backend service untouched.

Configure these repository Actions secrets before enabling deployment:

Go to **GitHub repository → Settings → Secrets and variables → Actions → New repository secret**
and add the following names exactly as shown. The workflow does not discover or trust an SSH host
key automatically.

| Secret | Value |
|---|---|
| `DEPLOY_HOST` | Instance DNS name or IP address |
| `DEPLOY_USER` | SSH deployment account |
| `DEPLOY_PATH` | Absolute checkout path, for example `/home/<user>/L7_Proxy` |
| `DEPLOY_SSH_KEY` | Private SSH key for the deployment account |
| `DEPLOY_KNOWN_HOSTS` | Pinned SSH host-key line for the instance |

Obtain the host key from the instance/admin console and verify its fingerprint out-of-band before
adding the complete `known_hosts` line as `DEPLOY_KNOWN_HOSTS`. Do not trust an unverified
`ssh-keyscan` result. The private key belongs only in `DEPLOY_SSH_KEY`; neither key should be
committed to this repository.

The instance must have Git, Docker Compose, the production `.env`, and a running Docker daemon.
The deploy account must be able to run `sudo -n docker compose` without an interactive password
(or have equivalent Docker permissions). Keep production secrets in the instance `.env`; do not
put them in the repository or workflow file.

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

### 앱 요청 검증과 조회 경로

앱 프록시는 `X-Timestamp`, `X-App-Version`, `X-Device-Id` 헤더를 검사하고
보호 경로에서는 JWT도 검증합니다. `/auth/` 경로는 로그인·토큰 발급을 위해
앱 헤더/JWT 검증을 거치지 않습니다. 최소 허용 앱 버전은 `APP_MIN_VERSION`
으로 설정하며 기본값은 `0.0.0`입니다. 레거시 `X-SignatureBase64` HMAC은
검증하지 않습니다.

환경변수 변경은 컨테이너 재생성이 필요하며 reload만으로 반영되지 않습니다.
운영 적용 시 기존 upstream, 비밀값, 배포 설정을 유지하세요.

`/places`, `/reservations`는 정확 일치 location으로 직접 전달하며 기존
하위 경로와 동일한 요청 제한 및 앱 검증을 적용합니다. 요청 URI와 쿼리를
유지하므로 슬래시 추가를 위한 301과 내부 포트 노출을 피합니다.

로컬 Lua 진입점 검증: `lua tests/app_entry_test.lua`.
실제 OpenResty 적용 전에는 설정 검사와 정상 JWT / 누락 JWT / 만료 JWT의
조회 검증이 필요합니다. 정상 요청에는 301 및 Location 헤더가 없어야 합니다.
운영 적용 후 문제가 발생하면 이전 설정·이미지·환경변수로 복원합니다.

### 앱 AI 대화 라우팅

`POST /ai/chat`은 앱 JWT·메타데이터 검사 후 프록시에서 Groq의
`/openai/v1/chat/completions`를 호출합니다. 공개 `AiChatRequest` /
`AiChatResponse` 형식은 프록시의 Lua 어댑터가 처리하며, AI 요청·연결 제한과
기존 timeout을 유지합니다.

모델은 서버 환경변수 `AI_MODEL`로 선택하며 기본값은 GPT-OSS 20B의
`openai/gpt-oss-20b`입니다. Groq API 키는 기존 `AI_API_KEY`를 사용합니다.
앱은 `model` 없이 `messages`와 선택적인 `tools`를 보냅니다. 모델·stream 등
공개 계약에 없는 provider 옵션과 URL 쿼리는 Groq에 전달하지 않습니다.
Groq 호출은 항상 비스트리밍입니다.

요청 예시 (`ACCESS_TOKEN`, `APP_VERSION`, `DEVICE_ID`는 앱의 기존 값):

```bash
curl 'https://www.typenull.xyz/ai/chat' \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H 'X-Client-Type: App' \
  -H 'Content-Type: application/json' \
  -H 'X-Request-Id: req_ai_chat_example' \
  -H "X-Timestamp: $(date +%s)" \
  -H "X-App-Version: ${APP_VERSION}" \
  -H "X-Device-Id: ${DEVICE_ID}" \
  --data '{"messages":[{"role":"user","content":"Hello"}],"tools":[]}'
```

일반 답변:

```json
{"content":"Hello","tool_calls":[]}
```

도구 응답:

```json
{"tool_calls":[{"id":"call_example","type":"function","function":{"name":"searchNearbyPlaces","arguments":{"keyword":"갈비탕"}}}]}
```

`messages`는 최대 50개이며 `user`, `assistant`, `tool`을 지원합니다. `tools`는
최대 20개의 function 정의를 지원합니다. 도구 호출의 `function.arguments`는
앱 요청·응답에서 JSON object입니다. 프록시는 Groq의 문자열 인자를 object로
해석하고, 앱이 보내는 assistant 호출 이력의 object 인자를 JSON 문자열로
변환합니다. `tool` 메시지의 object/array 결과도 JSON 문자열로 변환합니다.
도구 전용 응답에서 텍스트가 없으면 `content`를 생략합니다.

Groq의 `choices[0].message`만 공개 응답으로 변환하며, 등록되지 않은 도구,
잘못된 인자 JSON, 중복 호출 ID, 잘린 응답은 `502 PROVIDER_RESPONSE_INVALID`로
거절합니다. 앱 입력 오류는 400, 지원하지 않는 메서드는 405, JSON 외의
Content-Type은 415입니다. 키/모델 설정 오류는 503, Groq 호출 실패는 502,
Groq의 요청 제한은 429로 반환합니다. 오류는 `{"error":"코드"}` 형식이며
provider 응답 원문을 노출하지 않습니다. 기존 앱 인증 오류 처리는 유지합니다.

앱 JWT는 인증에만 사용합니다. 내부 Groq location은 외부 접근을 차단하며,
Groq에는 API 키와 JSON 본문, 추적 ID만 전달합니다. 앱 Cookie·메타데이터는
전달하지 않습니다. Groq TLS 인증서와 호스트를 검증합니다. JSON 요청 본문은
1 MiB로 제한하고, 내부 subrequest에서 비스트리밍 응답 전체를 수집한 뒤
2 MiB를 초과하면 거절합니다.

`X-Request-Id`는 영문/숫자/밑줄/하이픈으로 이루어진 최대 128자의 값이면
응답과 Groq 요청에 보존합니다. 없거나 유효하지 않으면 Nginx ID를 사용합니다.
AI 처리 로그에는 추적 ID, provider, 성공 모델, HTTP 상태, 고정된 결과 코드만
기록하고 JWT·API 키·사용자 본문·provider 응답은 기록하지 않습니다.

회귀 검증: `python3 tests/ai_chat_proxy_test.py`.
이미 설치된 `openresty/openresty:alpine` 이미지로 임시 컨테이너 1개와 로컬
HTTPS Groq fixture를 실행하고 종료 시 제거합니다. 원본 Nginx include 및
Lua 인증 흐름으로 모델 주입, 요청/응답 변환, 도구 후속 메시지, 내부 경로
차단, 인증 거절, 잘못된 provider 응답과 안전한 추적 로그를 검증합니다.
Rust FFI와 provider만 fixture로 대체하므로 실제 JWT 암호 검증·만료 판정,
Groq 계정의 모델 접근, 운영 TLS·배포는 별도 검증해야 합니다.

운영 적용 전 `.env`의 `AI_API_KEY`와 `AI_MODEL=openai/gpt-oss-20b`를 확인합니다.
환경변수 반영에는 컨테이너 재생성이 필요합니다. 렌더링 결과의 `/ai/chat`이
Lua 처리기로, 내부 경로가 Groq로 연결되는지 `openresty -T`로 확인하고
설정 검사를 실행합니다. 적용 후 실제 앱 요청으로 응답 형식과 추적 로그를
확인합니다. 문제가 발생하면 이전 이미지·설정·환경변수로 복원합니다.

모델 ID와 도구 호출 지원: [Groq GPT-OSS 20B 문서](https://console.groq.com/docs/model/openai/gpt-oss-20b).
