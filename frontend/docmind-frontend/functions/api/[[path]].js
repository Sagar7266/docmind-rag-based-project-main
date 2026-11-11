export async function onRequest({ request, env }) {
  if (!env.BACKEND_URL) {
    return new Response('BACKEND_URL is not configured.', { status: 500 });
  }

  const incoming = new URL(request.url);
  const target = new URL(
    incoming.pathname + incoming.search,
    env.BACKEND_URL
  );

  return fetch(new Request(target, request));
}
