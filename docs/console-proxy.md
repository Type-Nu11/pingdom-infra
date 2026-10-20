# 관리자 콘솔 라우팅

운영 서버에서 적용한 OpenResty 변경을 저장소 설정으로 반영합니다.

- `/console/`는 접두사를 제거한 뒤 내부 관리자 웹 컨테이너로 전달합니다.
- `/`·`/console`은 `/console/login`으로, 기존 `/operator/*`는 `/console/*`로 이동합니다.
  상대 Location을 사용해 HTTPS 앞단에 내부 HTTP 포트가 노출되지 않게 합니다.
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
```

배포 시 `docker-entrypoint.sh`가 환경변수 치환 후 OpenResty 설정을 검사합니다.
보호 경로의 무인증 상태는 웹 `/users/me`에서 401, 앱 `/users/me`에서 400이어야 합니다.
웹 루트 `/`는 이제 콘솔로 이동하므로 JWT 검사 대상으로 사용하지 않습니다.
