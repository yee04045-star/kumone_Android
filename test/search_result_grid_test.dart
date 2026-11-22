import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumone_flutter/core/api/netease_api.dart';
import 'package:kumone_flutter/core/models/models.dart';
import 'package:kumone_flutter/ui/pages/search_page.dart';
import 'package:kumone_flutter/ui/widgets/common.dart';

void main() {
  for (final width in [393.0, 1000.0]) {
    for (final type in [SearchType.albums, SearchType.artists, SearchType.playlists]) {
      testWidgets('search $type grid adapts at $width', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const data = SearchResult(
          albums: [AlbumSummary(id: 1, name: 'Album', artistName: 'Singer')],
          artists: [ArtistSummary(id: 2, name: 'Artist', picUrl: 'https://example.invalid/artist.jpg')],
          playlists: [PlaylistSummary(id: 3, name: 'Playlist', coverUrl: 'https://example.invalid/playlist.jpg')]);
        await tester.pumpWidget(MaterialApp(home: Scaffold(body:
          KumoneSearchResultGrid(data: data, type: type))));
        final delegate = tester.widget<GridView>(find.byType(GridView)).gridDelegate
            as SliverGridDelegateWithMaxCrossAxisExtent;
        expect(delegate.maxCrossAxisExtent, 190);
        final image = tester.widget<Artwork>(find.byType(Artwork));
        expect(image.circle, type == SearchType.artists);
        if (type == SearchType.artists) expect(image.size, 128);
        final name = type == SearchType.albums ? 'Album'
            : type == SearchType.artists ? 'Artist' : 'Playlist';
        final text = tester.widget<Text>(find.text(name));
        expect(text.maxLines, type == SearchType.playlists ? 2 : 1);
        expect(text.textAlign, type == SearchType.albums ? TextAlign.start : TextAlign.center);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
