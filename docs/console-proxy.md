# 관리자 콘솔 라우팅

운영 서버에서 적용한 OpenResty 변경을 저장소 설정으로 반영합니다.

- `/console/`는 접두사를 제거한 뒤 내부 관리자 웹 컨테이너로 전달합니다.
- `/`·`/console`은 `/console/login`으로, 기존 `/operator/*`는 `/console/*`로 이동합니다.
  상대 Location을 사용해 HTTPS 앞단에 내부 HTTP 포트가 노출되지 않게 합니다.
- 웹 프록시(8081)에서 API·콘솔·공개 경로로 등록되지 않은 주소도 `302 /console/login`으로 이동합니다.
  API namespace 내부의 잘못된 주소는 기존 JWT 인증과 백엔드 오류 처리를 유지합니다.
  새 최상위 API 경로를 추가하면 `configs/conf.d/web/locations.conf`의 API namespace 목록도 갱신합니다.
  앱 프록시(8082)의 인증·라우팅은 변경하지 않습니다.
- `/api/`는 경로를 유지해 웹 컨테이너의 API 프록시로 전달합니다.
  웹 컨테이너의 API upstream은 **웹 JWT 게이트웨이 8081**로 지정해야 합니다.
- OPTIONS는 JWT·앱 메타데이터 검사 전에 백엔드로 전달합니다. Origin·메서드·헤더 허용 여부는
  백엔드 CORS 정책이 판단합니다. 일반 요청은 기존 JWT·앱 메타데이터 검사를 거칩니다.

`CONSOLE_HOST` 기본값은 `BACKEND_HOST`, `CONSOLE_PORT`는 `8082`입니다.
관리자 웹이 다른 서버에 있으면 `.env`에 해당 서버의 **내부 주소**를 설정합니다.
프론트도 `/console/` base로 빌드해야 합니다. DNS·인증서·보안 그룹은 이 변경에 포함하지 않습니다.

Lua 회귀 검사(외부 JWT 라이브러리 대신 stub 사용):

```sh
lua tests/app_entry_test.lua
lua tests/web_entry_test.lua
python3 tests/swagger_public_test.py
python3 tests/web_routing_test.py
```

`web_routing_test.py`는 로컬 `nginx`(또는 `NGINX_BIN`)로 실제 location 선택과 상대 리다이렉트를
검증합니다. JWT Lua 대신 테스트용 `auth_request`를 사용하므로 실제 JWT 검증 테스트를 대체하지 않습니다.

배포 시 `docker-entrypoint.sh`가 환경변수 치환 후 OpenResty 설정을 검사합니다.
보호 경로의 무인증 상태는 웹 `/users/me`에서 401, 앱 `/users/me`에서 400이어야 합니다.
웹 루트 `/`는 이제 콘솔로 이동하므로 JWT 검사 대상으로 사용하지 않습니다.
