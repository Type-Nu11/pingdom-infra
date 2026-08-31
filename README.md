<img width="7680" height="4320" alt="e06df1f7888bc406" src="https://github.com/user-attachments/assets/945c1072-21d6-45c6-938d-21aabaea3beb" />


## Overview

이 저장소는 Pingdom 프로젝트의 **Infrastructure 및 Gateway 영역**을 관리합니다.

Pingdom 서비스의 외부 요청 진입점을 담당하는 Reverse Proxy Gateway로서,  
클라이언트 요청을 내부 서비스로 전달하고 서비스 보호를 위한 요청 제어 기능을 제공합니다.

OpenResty 기반 Gateway 환경에서 요청 라우팅, Rate Limit, 인증 처리, GeoIP 기반 네트워크 정보 처리 등을 수행하며  
Backend Server 및 내부 서비스가 안정적으로 동작할 수 있도록 앞단 계층을 제공합니다.

## Project Status

현재 **GA(General Availability)** 단계입니다.

안정화된 서비스를 제공하며, 기능, 구성, 인터페이스 및 제공 결과의 변경은 Release와
변경 이력을 통해 관리합니다.

| Item | Status |
|---|---|
| Development | `Generally Available` |
| Release | `GA` |
| Stability | `Stable` |

## Repository Role

| Item | Description |
|---|---|
| Type | `Infrastructure` |
| Responsibility | Pingdom 서비스 진입점 및 Reverse Proxy Gateway 관리 |
| Primary Output | Gateway 실행 환경 및 네트워크 처리 계층 |
| Target | Client Application, Backend Server 및 내부 서비스 |

## Scope

### Included

- Reverse Proxy 기반 요청 라우팅
- OpenResty Gateway 실행 환경 구성
- Rate Limit 기반 요청 제어
- 인증 관련 요청 처리
- GeoIP 기반 ASN 및 국가 정보 처리
- Docker 기반 Gateway 배포 환경 제공

### Not Included

- Backend Server 비즈니스 로직 처리
- 사용자 데이터 저장 및 관리
- 서비스 도메인 기능 구현
- 데이터베이스 운영 관리

## Key Capabilities

- **Reverse Proxy Gateway**: 외부 요청을 내부 서비스로 전달하고 서비스 진입점을 제공합니다.
- **Rate Limit 처리**: 요청량 제어를 통해 비정상적인 트래픽으로부터 서비스를 보호합니다.
- **인증 요청 처리**: Gateway 계층에서 인증 관련 요청 흐름을 관리합니다.
- **GeoIP 기반 네트워크 분석**: ASN 및 국가 정보를 활용한 요청 환경 분석을 제공합니다.

## Technology and Tools

| Category | Technology |
|---|---|
| Primary | Lua |
| Framework | OpenResty |
| Proxy Server | Nginx |
| Runtime | LuaJIT |
| Database | GeoLite2 Database |
| Delivery | Docker |

## Getting Started

이 저장소를 확인하거나 실행하기 위해 필요한 최소 절차입니다.

### Requirements

- Docker
- OpenResty
- LuaJIT
- GeoLite2 Database 파일
- Docker 실행 권한

### Setup

```bash
git clone https://github.com/Type-Nu11/pingdom-infra
cd pingdom-infra
```

Docker 이미지를 빌드합니다.

docker build -t pingdom-infra .
Usage
docker run -p 80:80 pingdom-infra

저장소 유형 및 배포 환경에 따라 실행 방식이 변경될 수 있습니다.

### Configuration

설정에 필요한 항목은 OpenResty 및 Nginx 설정 파일을 기준으로 구성합니다.

configs/nginx.conf.template
configs/conf.d/
src/init.lua
src/init_worker.lua

실제 인증정보, API Key, 비밀 값 및 운영 환경 정보는 저장소에 커밋하지 않습니다.

### Verification

저장소 변경사항은 다음 방법으로 검증합니다.

docker build -t pingdom-infra .
docker run -p 80:80 pingdom-infra

검증 방식이 여러 개인 경우 목적별로 구분합니다.

Verification	Purpose
docker build	Gateway 이미지 생성 검증
Docker 실행	OpenResty 실행 환경 검증
HTTP 요청 테스트	Proxy Routing 및 요청 처리 검증
Repository Structure
```
.
├── Dockerfile
├── README.md
├── configs
│   ├── conf.d
│   │   ├── locations
│   │   ├── log.conf
│   │   └── proxy.conf
│   └── nginx.conf.template
├── database
│   ├── GeoLite2-ASN.mmdb
│   └── GeoLite2-Country.mmdb
└── src
    ├── acme_file.lua
    ├── contents
    │   └── auth.lua
    ├── init.lua
    ├── init_worker.lua
    ├── modules
    │   ├── crawling.lua
    │   └── ratelimit.lua
    └── utils
        └── exceptions.lua
```

실제 구조를 기준으로 주요 디렉터리와 파일만 설명합니다.

Related Repositories
Repository	Relationship
pingdom-server	Gateway를 통해 요청을 전달받는 Backend Server
pingdom-mcp	AI 기반 데이터 처리 및 MCP 서비스 연동

공개되어 있거나 접근 가능한 저장소만 연결합니다.

### Documentation
Document	Description
리버스프록시문서	Gateway 구성 및 운영 관련 문서

실제로 존재하며 공개 가능한 문서만 연결합니다.

Release and Compatibility

현재 버전은 GA(General Availability) 단계입니다.

호환성에 영향을 주는 변경사항은 Release와 관련 문서를 통해 안내합니다.
변경사항은 저장소의 Release 또는 변경 이력을 기준으로 확인합니다.
### License

이 프로젝트의 사용 및 배포 조건은 MIT LICENSE를 따릅니다.

Part of Pingdom
