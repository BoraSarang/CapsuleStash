/* T-49 Safari Web Extension 팝업. 현재 탭의 제목·URL을 capsule://save로 넘긴다.
 * 앱 쪽 처리는 검증됨 (T-53 실동작 확인). 선택 텍스트 저장은 2단계 (content script). */
async function currentTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return tab;
}

function capsuleSaveURL(title, url) {
  const params = new URLSearchParams({ text: title || "", url: url || "" });
  // Swift URLComponents는 `+`를 공백으로 안 푼다 — %20으로 통일한다.
  return `capsule://save?${params.toString().replace(/\+/g, "%20")}`;
}

if (typeof document !== "undefined") {
  document.addEventListener("DOMContentLoaded", async () => {
    const label = document.getElementById("tab");
    const status = document.getElementById("status");
    try {
      const tab = await currentTab();
      label.textContent = tab?.title || tab?.url || "(탭 없음)";
      document.getElementById("save").addEventListener("click", async () => {
        const t = await currentTab();
        if (!t?.url) {
          status.textContent = "저장할 탭이 없습니다.";
          return;
        }
        // 새 탭으로 capsule:// URL을 열면 앱이 이어받는다.
        await chrome.tabs.create({ url: capsuleSaveURL(t.title, t.url), active: false });
        status.textContent = "수신함에 저장했습니다.";
      });
    } catch (e) {
      label.textContent = "탭을 읽지 못했습니다.";
    }
  });
}

// 테스트용 pure 함수 노출 (node --test 검증)
if (typeof module !== "undefined") {
  module.exports = { capsuleSaveURL };
}
