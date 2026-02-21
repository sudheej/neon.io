export default async (request: Request, context: { next: () => Promise<Response> }) => {
  const username = Deno.env.get("PLAYTEST_USER") || "";
  const password = Deno.env.get("PLAYTEST_PASS") || "";

  // Fail closed if secrets were not configured in Netlify.
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
          return context.next();
        }
      }
    } catch (_err) {
      // fall through to 401
    }
  }

  return new Response("Authentication required", {
    status: 401,
    headers: {
      "WWW-Authenticate": 'Basic realm="Neon Playtest", charset="UTF-8"'
    }
  });
};
