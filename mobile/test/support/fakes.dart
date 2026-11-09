import 'package:readlater/core/api/api_client.dart';
import 'package:readlater/core/api/errors.dart';
import 'package:readlater/core/config/key_value_store.dart';
import 'package:readlater/core/config/config_store.dart';
import 'package:readlater/core/models/health.dart';
import 'package:readlater/core/models/link.dart';
import 'package:readlater/core/models/site.dart';
import 'package:readlater/core/storage/session_store.dart';
import 'package:readlater/core/web/title_resolver.dart';

/// 内存键值存储（测试用）。
class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

/// 用内存存储预置服务器配置（测试用）。
ConfigStore fakeConfigStore({required String baseUrl, required String apiKey}) {
  final store = InMemoryKeyValueStore();
  store.values[ConfigStore.storageKey] =
      '{"baseUrl":"$baseUrl","apiKey":"$apiKey","enabled":true}';
  return ConfigStore(store);
}

/// 内存会话存储（测试用）。
class InMemorySessionStore implements SessionStore {
  SessionData? data;
  int saveCount = 0;

  @override
  Future<SessionData?> load() async => data;

  @override
  Future<void> save(SessionData value) async {
    data = value;
    saveCount++;
  }
}

/// 固定元信息的解析器（测试用）。
class FakePageMetaResolver implements PageMetaResolver {
  FakePageMetaResolver({this.meta = const PageMeta()});

  PageMeta meta;

  @override
  Future<PageMeta> resolve(String url) async => meta;
}

/// 可注入异常的假 API 客户端（测试用）。
class FakeApiClient implements ApiClient {
  FakeApiClient({
    this.links = const [],
    this.total,
    this.sites = const [],
    this.siteTrash = const [],
    this.trash = const [],
    this.linkExistsResult = const ExistsResult(exists: false),
    this.siteExistsResult = const SiteExistsResult(exists: false, inTrash: false),
    this.error,
  });

  List<LinkItem> links;
  int? total;
  List<Site> sites;
  List<Site> siteTrash;
  List<TrashItem> trash;
  ExistsResult linkExistsResult;
  SiteExistsResult siteExistsResult;
  ApiException? error;

  final List<String> deletedLinkIds = [];
  final List<String> deletedSiteIds = [];
  final List<AddLinkRequest> addedLinks = [];
  final List<SiteInput> addedSites = [];

  @override
  Future<HealthStatus> health() async {
    _throwIfError();
    return const HealthStatus(ok: true);
  }

  @override
  Future<ExistsResult> linkExists(String url) async {
    _throwIfError();
    return linkExistsResult;
  }

  @override
  Future<void> addLink(AddLinkRequest req) async {
    _throwIfError();
    addedLinks.add(req);
  }

  @override
  Future<PagedLinks> listLinks({
    int page = 1,
    int pageSize = 50,
    String? search,
    String? domain,
    String sortBy = 'created_at',
    String sortOrder = 'desc',
  }) async {
    _throwIfError();
    return PagedLinks(links: links, total: total ?? links.length);
  }

  @override
  Future<void> deleteLink(String id) async {
    _throwIfError();
    deletedLinkIds.add(id);
  }

  @override
  Future<List<TrashItem>> listTrash() async {
    _throwIfError();
    return trash;
  }

  @override
  Future<void> restoreTrash(String id) async {
    _throwIfError();
  }

  @override
  Future<void> purgeTrash(String id) async {
    _throwIfError();
  }

  @override
  Future<List<Site>> listSites() async {
    _throwIfError();
    return sites;
  }

  @override
  Future<Site> addSite(SiteInput input) async {
    _throwIfError();
    addedSites.add(input);
    return Site(
      id: 'site_${addedSites.length}',
      url: input.url,
      title: input.title,
      iconUrl: input.iconUrl,
      createdAt: 1,
    );
  }

  @override
  Future<void> deleteSite(String id) async {
    _throwIfError();
    deletedSiteIds.add(id);
  }

  @override
  Future<List<Site>> listSiteTrash() async {
    _throwIfError();
    return siteTrash;
  }

  @override
  Future<void> restoreSite(String id) async {
    _throwIfError();
  }

  @override
  Future<void> purgeSite(String id) async {
    _throwIfError();
  }

  @override
  Future<SiteExistsResult> siteExists(String url) async {
    _throwIfError();
    return siteExistsResult;
  }

  void _throwIfError() {
    final e = error;
    if (e != null) throw e;
  }
}
