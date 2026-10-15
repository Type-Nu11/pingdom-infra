# PingCha

## 활성화 인터페이스

`.env`의 `PINGCHA_ENABLED=true`로 켜고 `PINGCHA_ENABLED=false`로 끕니다. 기본값은 false이며 true/false 이외의 값은 시작 시 거부합니다. false일 때는 로그인 차단, HTML/모달 삽입, CSP 수정, 콘솔 압축·캐시 요청 헤더 변경을 모두 건너뜁니다. 기존 JWT 검증은 계속 적용합니다. 공개 HTTP API로 설정을 변경하지는 않습니다.

최초 코드 배포는 `docker compose up -d --build --no-deps reverse-proxy`로 반영하세요. 이후 `.env`의 on/off 값만 바꿀 때는 `docker compose up -d --force-recreate --no-deps reverse-proxy`로 컨테이너를 다시 생성해야 합니다. restart만으로는 변경된 환경변수가 반영되지 않습니다.

조회 인터페이스는 `GET /_pingdom/pingcha/status`입니다. JSON의 `enabled`와 `verified`가 boolean으로 반환됩니다. 예: 켜짐/미통과는 `{"enabled":true,"verified":false}`, 켜짐/통과는 `{"enabled":true,"verified":true}`, 꺼짐은 `{"enabled":false,"verified":false}`입니다. verified는 서버 쿠키를 확인한 결과이며, 비활성화 상태를 성공으로 위장하지 않습니다. 활성화 여부를 프런트엔드 값으로 변경해도 서버 검사를 우회할 수 없습니다.

Figma의 세 상태를 HTML/CSS/JS로 구현했습니다. 원본 디자인 601×130을 기본 360×78로 축소하며, 모바일에서는 가용 폭에 맞춥니다. 실행 화면은 박스만 표시합니다. SVG와 Pretendard 글꼴은 로컬 자산입니다.

실제 실행 주소는 웹 프록시(8081)의 `/_pingdom/captcha/`입니다. file://나 Python 정적 서버는 외형만 확인할 수 있으며 서버 검증을 수행하지 않습니다. 운영은 HTTPS가 필요합니다. 로컬 테스트는 localhost를 사용하세요.

`/console/`의 HTML은 프록시의 header/body filter가 nonce를 붙인 `modal.js`를 삽입합니다. 로그인 페이지는 200 응답으로 그대로 보이고, 검증이 필요할 때만 반투명 배경과 작은 PingCha 모달이 표시됩니다. 성공 후 서버 status API로 쿠키를 재확인하고 모달만 닫습니다. 부모/자식 메시지의 origin과 source를 확인하므로 임의의 성공 메시지로는 통과할 수 없습니다. fetch, 비동기 XHR(Axios), native submit 이벤트를 통해 로그인 자격 증명을 보내기 전에 검증을 확인하며, 전송 완료된 POST를 자동 재전송하지 않습니다.

직접 삽입할 때는 같은 origin의 `/_pingdom/captcha/?embed=1`을 iframe으로 사용할 수 있습니다(가로 360px, 박스 높이 약 78px). embed 모드는 바깥 여백과 전체 화면 중앙 배치를 제거하며, 완료 뒤 iframe 자체가 다른 페이지로 이동하지 않습니다. 기본 모달은 iframe의 resize 메시지로 오류 메시지 높이도 자동 조정합니다.

웹 콘솔 upstream의 Accept-Encoding 및 조건부 캐시 헤더를 제거해 수정 가능한 HTML을 요청하고, 수정 응답은 no-store로 전달합니다. 필터는 성공한 text/html만 수정하며 전체 HTML을 버퍼링하지 않습니다. JSON, CSS, 이미지 및 앱 프록시 응답에는 스크립트를 삽입하지 않습니다. CSP 응답 헤더는 기존 제한을 보존하면서 로더/스타일 nonce와 same-origin iframe/connect 소스만 추가합니다. upstream이 압축 금지를 무시하거나 HTML meta CSP 또는 sandbox로 스크립트를 제한하면 추가 설정이 필요합니다. 압축된 응답은 손상시키지 않고 삽입을 건너뛰며 경고를 기록합니다. 로그인 API의 서버 검증은 이 경우에도 유지됩니다.

체크박스를 클릭하면 runtime.js가 검증을 시작합니다. 클릭 전에는 챌린지를 발급하거나 작업 증명을 계산하지 않습니다. 서버가 발급한 120초짜리 일회용 nonce에 대해 Worker가 SHA-256 10비트 작업 증명을 계산합니다. Worker는 한 개만 실행하며 한 번에 최대 16,384회/1.5초, 응답 대기는 2.5초로 제한합니다. 실패 시 자동 반복하지 않고 체크박스로 재시도합니다. 서버에서 증명과 User-Agent를 확인하고 원자적으로 소모한 뒤 15분짜리 `__Host-pingcha` 쿠키(Secure, HttpOnly, SameSite=Lax)를 발급합니다. 브라우저가 쿠키를 수락한 것도 확인한 후 성공으로 표시합니다.

검증 성공 시 “인증되었습니다”를 약 1초 표시한 뒤 서버 쿠키를 재확인하고 모달을 닫거나 원래 페이지로 이동합니다. 추가 확인 버튼은 없습니다. 페이지를 떠나면 대기 중 타이머를 정리하고, 만료·네트워크 오류 시에는 재시도를 안내합니다.

웹 서버의 공개 location들은 서버 수준 PingCha access handler를 상속합니다. 기존 JWT location은 자체 access handler를 유지합니다. `/auth/`와 `/api/auth/` 요청, 공개 콘솔 HTML 화면, Swagger HTML 및 API 문서 요청이 대상입니다. 헬스체크, 정적 리소스, OPTIONS, refresh/logout 및 OAuth callback은 제외합니다. 앱 서버(8082)에는 적용하지 않습니다. 콘솔 HTML은 모달 방식이며, Swagger HTML은 기존 검증 페이지 복귀 방식입니다. POST/API 요청은 본문을 리다이렉트하지 않고 403 `PINGCHA_REQUIRED`와 `challenge_url`을 반환합니다. 삽입된 로더가 없는 외부 프런트엔드는 이 응답을 처리해 검증 UI를 연 후 사용자가 요청을 다시 제출하도록 해야 합니다.

`captcha.js`는 표시 전용 컴포넌트입니다. `pingdom:verify` 요청 이벤트와 runtime의 `pingcha:verified` 완료 이벤트를 지원합니다. `setState("success")`를 직접 호출해도 서버 쿠키를 만들 수 없으므로 서버 차단을 우회할 수 없습니다. embed runtime은 같은 origin의 부모에게만 postMessage로 완료/크기 변경을 알립니다.

이 구현은 가벼운 브라우저 작업 증명이며 인간임을 판별하는 외부 CAPTCHA 서비스를 대체하지 않습니다. 일반 봇도 챌린지를 풀 수 있으므로 JWT·요청 제한을 계속 사용해야 합니다. 상태는 OpenResty shared dict에 보관되므로 재시작 시 재검증하며, 여러 게이트웨이 복제본을 운영할 때는 공유 저장소 또는 세션 고정이 추가로 필요합니다. 챌린지 속도 제한의 IP는 현재 연결 주소이므로 실제 IP 복원은 신뢰하는 상위 프록시 설정으로 별도 관리해야 합니다.

검증: `lua tests/web_entry_test.lua`, `lua tests/app_entry_test.lua`, `lua tests/pingcha_html_test.lua`, `node tests/pingcha_runtime_test.cjs`, `node tests/pingcha_modal_test.cjs` 및 격리 OpenResty 환경에서 `python3 tests/pingcha_integration_test.py`. `tests/pingcha_backend.conf`는 테스트 upstream과 만료 fixture 전용이며 운영에 포함하면 안 됩니다.
