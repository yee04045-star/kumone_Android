String artworkUrl(String raw, {required bool thumbnail}) {
  var value = raw.trim();
  if (value.startsWith('//')) value = 'https:$value';
  if (value.startsWith('http://')) value = 'https:${value.substring(5)}';
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.host.endsWith('.music.126.net')) return value;
  final size = thumbnail ? 192 : 768;
  return uri.replace(queryParameters: {
    ...uri.queryParameters, 'param': '${size}y$size',
  }).toString();
}
