# 공개 Swagger/OpenAPI HTTPS 설정

백엔드 이슈: https://github.com/Type-Nu11/pingdom-api/issues/1751

## 변경 범위

`/v3/api-docs` exact location은 slash를 붙이는 Nginx 자동 301 없이 원래 경로를 전달한다.
Swagger UI 안내 리다이렉트는 상대 경로를 사용한다. 기존 그룹 URL은 유지한다.

`openapi_proxy_header.conf`는 Swagger/OpenAPI location에만 적용한다.
일반 API의 Lua/JWT/HMAC 처리와 공통 헤더 파일은 변경하지 않는다.
백엔드의 문서 공개·인증 토글은 별도로 적용되므로 이 구성만으로 전체 API가 공개되지 않는다.

## 운영 적용 전 확인

1. TLS 종료부터 OpenResty와 Spring까지 실제 upstream, 실행 이미지와 설정을 확인한다.
   저장소 소스와 운영 실행 설정이 일치한다고 추정하지 않는다.
2. 기존 설정을 백업하고 실제 upstream 주소는 유지한다. `BACKEND_HOST:BACKEND_PORT`는
   기존 운영 방식으로 치환한다. 백엔드 주소 변경은 이 작업의 범위가 아니다.
3. OpenResty가 관찰하는 직접 연결 TLS/중간 프록시 IP만
   `configs/conf.d/shared/openapi_trusted_proxies.conf`에 추가한다. 기본 allowlist는 loopback뿐이다.
   컨테이너 NAT가 있으면 변환 후 peer IP를 확인한다. 전체 인터넷·사설망을 허용하지 않는다.
4. 앞단 프록시는 외부 Host를 유지하고 외부 클라이언트가 보낸 forwarded 헤더를 제거하거나
   정상 값으로 덮어쓴다. TLS 종료 지점의 `X-Forwarded-Proto: https`를 이후 hop이 보존해야 한다.
5. Spring의 `TRUSTED_PROXY_IPS_REGEX`에는 Spring이 직접 관찰하는 OpenResty IP를 지정한다.
   이 IP와 OpenResty allowlist의 앞단 프록시 IP는 서로 다를 수 있다.
6. 기존 문서 공개 정책을 유지하고 `openresty -t`로 실제 실행 설정을 검증한 뒤 반영한다.

신뢰하지 않는 peer의 `X-Forwarded-Proto`와 client IP는 무시한다. 중복되거나 혼합된 scheme도
신뢰하지 않는다. 문서의 host는 수신 Host에서 결정하며 입력 `X-Forwarded-Host`는 덮어쓴다.
`Forwarded`는 제거한다. 공개 API는 기본 포트 HTTP 80/HTTPS 443을 사용하며 내부 8081은 전달하지 않는다.
비표준 공개 포트가 필요하면 port 정책과 테스트를 별도로 변경해야 한다.

## 로컬 검증

```bash
python3 tests/openapi_proxy_test.py
```

Docker와 Python 3가 필요하다. 테스트는 원본 `nginx.conf`와 전체 include 구조를 임시 디렉터리에
복사하고 upstream과 Lua guard만 fixture로 치환한다. 임시 OpenResty 컨테이너는 종료 시 정리한다.
문서 8개 경로, root query 보존, 상대 리다이렉트, 신뢰/비신뢰 peer의 헤더와 혼합 scheme을 검증한다.
일반 경로의 Lua 인증은 401 fixture로 대체하므로 실제 JWT 검증, TLS 종료, 운영 upstream 검증은 포함하지 않는다.
HTTP 요청은 5초, subprocess는 기본 30초, 컨테이너 정리는 10초로 제한한다.
종료 신호를 받아도 정리를 시도하며 Docker 장애로 정리에 실패하면 실행 오류를 반환한다.

실제 Spring과의 연결은 백엔드 checkout에서 실행한다. `PINGDOM_INFRA_TEST_ROOT`에는 이 저장소의 절대 경로를 지정한다.

```bash
PINGDOM_INFRA_TEST_ROOT=/absolute/path/to/pingdom-infra ./gradlew integrationTest --tests '*ForwardedHeadersIntegrationTest' --tests '*SwaggerProductionSecurityTest'
```

Spring 공개 토글이 켜지면 직접/loopback 두 peer의 문서 경로 8개가 200을 반환하고 신뢰 peer의
root/그룹 서버 URL이 HTTPS여야 한다. 공개 토글이 꺼지면 두 peer에서 모두 401이어야 한다.
Java 검증기는 120초 뒤 종료를 요청한다. 환경변수가 없으면 두 연동 테스트는 skip된다.

2026-10-01 OpenResty 1.31.1.1에서 원본 설정 구문 검사와 독립 검증 14개가 통과했다.
실제 Spring 연결의 공개/비공개 검증도 통과했다. Docker Desktop의 로컬 네트워크 결과이므로
운영 NAT peer, TLS 체인과 실행 설정은 배포 시 별도로 확인한다.

## 운영 검증 및 롤백

- 리다이렉트를 추적하지 않고 공개 root, 다섯 그룹, swagger-config와 UI/정적 리소스를 확인한다.
- root가 내부 HTTP/8081로 유도하지 않아야 한다. 그룹의 `servers[].url`은 실제 HTTPS base URL과 일치해야 한다.
- 실제 HTTPS Swagger Try It Out에서 승인된 읽기 API를 기존 인증으로 실행하고 HTTP downgrade와
  mixed-content 부재를 Network/Console에서 확인한다. 토큰·개인정보를 기록하지 않는다.
- 일반 보호 API의 인증 거부와 백엔드의 문서 비공개 정책이 유지되는지 확인한다.

실패하면 변경된 `nginx.conf`, 문서 location, HTTP map, 문서 헤더·allowlist 및 앞단 TLS 설정을 복원한다.
이전 이미지로 복구해도 외부 mount·환경변수 변경은 별도로 복원해야 한다.
백엔드의 신뢰 설정을 함께 변경했다면 해당 값과 필요한 backend 이미지도 복구한다.
