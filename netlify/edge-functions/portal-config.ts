export default async (request: Request) => {
  const username = Deno.env.get("PLAYTEST_USER") || "";
  const password = Deno.env.get("PLAYTEST_PASS") || "";
  if (!username || !password) {
    return new Response("Playtest portal is not configured.", { status: 503 });
  }

  const auth = request.headers.get("authorization") || "";
  if (auth.startsWith("Basic ")) {
    try {
      const encoded = auth.slice(6).trim();
      const decoded = atob(encoded);
      const splitAt = decoded.indexOf(":");
      if (splitAt >= 0) {
        const user = decoded.slice(0, splitAt);
        const pass = decoded.slice(splitAt + 1);
        if (user === username && pass === password) {
          // continue
        } else {
          return new Response("Authentication required", {
            status: 401,
            headers: { "WWW-Authenticate": 'Basic realm="Neon Playtest", charset="UTF-8"' }
          });
        }
      } else {
        return new Response("Authentication required", {
          status: 401,
          headers: { "WWW-Authenticate": 'Basic realm="Neon Playtest", charset="UTF-8"' }
        });
      }
    } catch (_err) {
      return new Response("Authentication required", {
        status: 401,
        headers: { "WWW-Authenticate": 'Basic realm="Neon Playtest", charset="UTF-8"' }
      });
    }
  } else {
    return new Response("Authentication required", {
      status: 401,
      headers: { "WWW-Authenticate": 'Basic realm="Neon Playtest", charset="UTF-8"' }
    });
  }

  const linuxUrl = Deno.env.get("PLAYTEST_LINUX_URL") || "https://example.com/neon/linux";
  const windowsUrl = Deno.env.get("PLAYTEST_WINDOWS_URL") || "https://example.com/neon/windows";
  const buildStamp = Deno.env.get("PLAYTEST_BUILD_STAMP") || new Date().toISOString().slice(0, 19).replace("T", " ") + " UTC";

  return new Response(
    JSON.stringify({
      linux_url: linuxUrl,
      windows_url: windowsUrl,
      build_stamp: buildStamp
    }),
    {
      status: 200,
      headers: {
        "content-type": "application/json; charset=utf-8",
        "cache-control": "no-store"
      }
    }
  );
};
