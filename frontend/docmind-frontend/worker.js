export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname.startsWith('/api/')) {
      if (!env.BACKEND_URL) {
        return new Response('BACKEND_URL is not configured.', { status: 500 });
      }

      const target = new URL(url.pathname + url.search, env.BACKEND_URL);
      console.log('API request:', url.pathname);
      const response = await fetch(new Request(target, request));
      console.log('Backend status:', response.status);
      return response;
    }

    return env.ASSETS.fetch(request);
  },
};
