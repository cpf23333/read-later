import '../models/link.dart';
import '../models/domain_stat.dart';
import '../models/site.dart';
import '../models/health.dart';

/// 服务器 API 客户端接口（便于测试替换）。
abstract class ApiClient {
  Future<HealthStatus> health();

  Future<ExistsResult> linkExists(String url);
  Future<void> addLink(AddLinkRequest req);
  Future<PagedLinks> listLinks({
    int page = 1,
    int pageSize = 50,
    String? search,
    String? domain,
    String sortBy = 'created_at',
    String sortOrder = 'desc',
  });
  Future<void> deleteLink(String id);
  Future<void> batchDeleteLinks(List<String> ids);
  Future<void> updateLink(
    String id, {
    String? title,
    String? nearbyImage,
    String? screenshot,
  });
  Future<List<DomainStat>> listDomains();

  Future<List<TrashItem>> listTrash();
  Future<void> restoreTrash(String id);
  Future<void> purgeTrash(String id);
  Future<void> batchRestoreTrash(List<String> ids);
  Future<void> batchPurgeTrash(List<String> ids);

  Future<List<Site>> listSites();
  Future<Site> addSite(SiteInput input);
  Future<Site> updateSite(
    String id, {
    String? title,
    String? iconUrl,
    String? userAgentMode,
    String? userAgent,
  });
  Future<void> deleteSite(String id);
  Future<List<Site>> listSiteTrash();
  Future<void> restoreSite(String id);
  Future<void> purgeSite(String id);
  Future<SiteExistsResult> siteExists(String url);
}
