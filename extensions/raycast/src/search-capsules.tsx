import { open, showToast, Toast } from "@raycast/api";

interface Arguments {
  query: string;
}

/** T-54 Raycast 검색. 앱의 capsule://search로 넘기고 앱이 이어받는다. */
export default async function Command(props: { arguments: Arguments }) {
  const query = props.arguments.query.trim();
  if (!query) {
    await showToast({ style: Toast.Style.Failure, title: "검색어를 입력하세요" });
    return;
  }
  const url = `capsule://search?query=${encodeURIComponent(query)}`;
  await open(url);
}
