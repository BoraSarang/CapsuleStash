import { Clipboard, showToast, Toast } from "@raycast/api";
import { writeFile, mkdir } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { randomUUID } from "node:crypto";

/**
 * T-54 Raycast 클립보드 저장. 수신함 파일 규격(InboxPayload)과 같은 JSON을 떨군다.
 * 본체가 다음에 창을 열 때 Inbox 문서로 편입한다.
 */
export default async function Command() {
  const text = (await Clipboard.readText())?.trim();
  if (!text) {
    await showToast({ style: Toast.Style.Failure, title: "클립보드가 비어 있습니다" });
    return;
  }
  const dir = join(homedir(), "Library", "Application Support", "CapsuleStash", "Inbox");
  await mkdir(dir, { recursive: true });
  const payload = JSON.stringify({ version: 1, text, source: "Raycast" });
  const file = join(dir, `inbox-${randomUUID()}.json`);
  await writeFile(file, payload, { flag: "wx" });
  await showToast({ style: Toast.Style.Success, title: "수신함에 저장했습니다" });
}
