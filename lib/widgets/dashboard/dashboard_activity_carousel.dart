import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/local_app_database.dart';
import '../../state/dashboard/dashboard_state.dart';
import '../../theme/app_colors.dart';

class DashboardActivityCarousel extends StatefulWidget {
  const DashboardActivityCarousel({super.key});

  @override
  State<DashboardActivityCarousel> createState() =>
      _DashboardActivityCarouselState();
}

class _DashboardActivityCarouselState extends State<DashboardActivityCarousel> {
  static const _pageSize = 50;
  static const _cacheTtl = Duration(hours: 4);

  final _controller = PageController();
  late Future<List<_DashboardActivitySection>> _future;
  List<_DashboardActivitySection>? _sections;
  final _loadingMore = <String>{};
  final _exhausted = <String>{};
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<List<_DashboardActivitySection>> _load() async {
    final appState = context.read<DashboardState>();
    final cacheKey = _cacheKey(appState);
    final cached = await LocalAppDatabase.instance.readJson(cacheKey);
    final cachedSections = _sectionsFromCache(cached);
    if (cachedSections != null) {
      _applySections(cachedSections);
      unawaited(
        _refreshRemote(cacheKey, updateState: true).catchError((_) {
          return cachedSections;
        }),
      );
      return cachedSections;
    }

    return _refreshRemote(cacheKey);
  }

  Future<List<_DashboardActivitySection>> _refreshRemote(
    String cacheKey, {
    bool updateState = false,
  }) async {
    final sections = await _fetchRemoteSections();
    await _writeCache(cacheKey, sections);
    _applySections(sections);
    if (updateState && mounted) {
      setState(() {
        _future = Future.value(sections);
      });
    }
    return sections;
  }

  Future<List<_DashboardActivitySection>> _fetchRemoteSections() async {
    final appState = context.read<DashboardState>();
    final service = appState.frappeService;

    final sections = await Future.wait([
      _fetchSection(
        title: 'Activity Log',
        subtitle: 'Aktivitas terbaru dari ERPNext',
        icon: Icons.history_rounded,
        color: AppColors.primary,
        fetch: () => _fetchWithFallback(
          service,
          doctype: 'Activity Log',
          limitStart: 0,
          fieldSets: const [
            [
              'name',
              'subject',
              'content',
              'reference_doctype',
              'reference_name',
              'owner',
              'creation',
            ],
            ['name', 'subject', 'owner', 'creation'],
            ['name', 'owner', 'creation'],
            ['name'],
          ],
        ),
      ),
      _fetchSection(
        title: 'Route History',
        subtitle: 'Riwayat route terbaru',
        icon: Icons.route_rounded,
        color: const Color(0xFF0891B2),
        fetch: () => _fetchWithFallback(
          service,
          doctype: 'Route History',
          limitStart: 0,
          fieldSets: const [
            [
              'name',
              'route',
              'user',
              'reference_doctype',
              'reference_name',
              'creation',
            ],
            ['name', 'route', 'user', 'creation'],
            ['name', 'owner', 'creation'],
            ['name'],
          ],
        ),
      ),
      _fetchSection(
        title: 'Version',
        subtitle: 'Perubahan dokumen terakhir',
        icon: Icons.restore_rounded,
        color: const Color(0xFF2563EB),
        fetch: () => _fetchWithFallback(
          service,
          doctype: 'Version',
          limitStart: 0,
          fieldSets: const [
            ['name', 'ref_doctype', 'docname', 'owner', 'creation'],
            ['name', 'docname', 'owner', 'creation'],
            ['name', 'owner', 'creation'],
            ['name'],
          ],
        ),
      ),
    ]);

    return sections;
  }

  void _applySections(List<_DashboardActivitySection> sections) {
    _sections = sections;
    _exhausted
      ..clear()
      ..addAll(
        sections
            .where((section) => section.rows.length < _pageSize)
            .map((section) => section.title),
      );
  }

  Future<void> _writeCache(
    String cacheKey,
    List<_DashboardActivitySection> sections,
  ) {
    return LocalAppDatabase.instance.writeJson(cacheKey, {
      'sections': sections.map((section) => section.toJson()).toList(),
    }, ttl: _cacheTtl);
  }

  Future<void> _loadMore(_DashboardActivitySection section) async {
    final title = section.title;
    if (_loadingMore.contains(title) || _exhausted.contains(title)) return;

    final cacheKey = _cacheKey(context.read<DashboardState>());
    final currentSections = _sections ?? await _future;
    final index = currentSections.indexWhere((item) => item.title == title);
    if (index < 0) return;
    final current = currentSections[index];

    setState(() => _loadingMore.add(title));
    try {
      final rows = await _fetchSectionPage(
        title,
        limitStart: current.rows.length,
      );
      final nextItems = rows.map(_DashboardActivityItem.fromJson).toList();
      if (nextItems.length < _pageSize) _exhausted.add(title);
      if (nextItems.isEmpty) return;

      final nextSections = [...currentSections];
      nextSections[index] = current.copyWith(
        rows: [...current.rows, ...nextItems],
      );
      _sections = nextSections;
      await _writeCache(cacheKey, nextSections);
      if (!mounted) return;
      setState(() {
        _future = Future.value(nextSections);
      });
    } catch (_) {
      _exhausted.add(title);
    } finally {
      if (mounted) setState(() => _loadingMore.remove(title));
    }
  }

  Future<List<Map<String, dynamic>>> _fetchSectionPage(
    String title, {
    required int limitStart,
  }) {
    final service = context.read<DashboardState>().frappeService;
    switch (title) {
      case 'Activity Log':
        return _fetchWithFallback(
          service,
          doctype: 'Activity Log',
          limitStart: limitStart,
          fieldSets: const [
            [
              'name',
              'subject',
              'content',
              'reference_doctype',
              'reference_name',
              'owner',
              'creation',
            ],
            ['name', 'subject', 'owner', 'creation'],
            ['name', 'owner', 'creation'],
            ['name'],
          ],
        );
      case 'Route History':
        return _fetchWithFallback(
          service,
          doctype: 'Route History',
          limitStart: limitStart,
          fieldSets: const [
            [
              'name',
              'route',
              'user',
              'reference_doctype',
              'reference_name',
              'creation',
            ],
            ['name', 'route', 'user', 'creation'],
            ['name', 'owner', 'creation'],
            ['name'],
          ],
        );
      case 'Version':
        return _fetchWithFallback(
          service,
          doctype: 'Version',
          limitStart: limitStart,
          fieldSets: const [
            ['name', 'ref_doctype', 'docname', 'owner', 'creation'],
            ['name', 'docname', 'owner', 'creation'],
            ['name', 'owner', 'creation'],
            ['name'],
          ],
        );
      default:
        return Future.value(const []);
    }
  }

  String _cacheKey(DashboardState appState) {
    return [
      'dashboard_activity_cache',
      appState.selectedSiteBaseUrl.trim(),
      appState.currentUser?.trim() ?? '',
    ].join('|');
  }

  List<_DashboardActivitySection>? _sectionsFromCache(
    Map<String, dynamic>? json,
  ) {
    final rows = json?['sections'];
    if (rows is! List) return null;
    final byTitle = <String, List<_DashboardActivityItem>>{};
    for (final row in rows) {
      if (row is! Map) continue;
      final title = row['title']?.toString() ?? '';
      final rawItems = row['rows'];
      if (title.isEmpty || rawItems is! List) continue;
      byTitle[title] = rawItems
          .whereType<Map>()
          .map((item) => _DashboardActivityItem.fromCache(item))
          .toList();
    }
    if (byTitle.isEmpty) return null;
    return _loadingSections.map((section) {
      return section.copyWith(rows: byTitle[section.title] ?? const []);
    }).toList();
  }

  Future<_DashboardActivitySection> _fetchSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Future<List<Map<String, dynamic>>> Function() fetch,
  }) async {
    try {
      final rows = await fetch();
      return _DashboardActivitySection(
        title: title,
        subtitle: subtitle,
        icon: icon,
        color: color,
        rows: rows.map(_DashboardActivityItem.fromJson).toList(),
      );
    } catch (_) {
      return _DashboardActivitySection(
        title: title,
        subtitle: subtitle,
        icon: icon,
        color: color,
        rows: const [],
      );
    }
  }

  Future<List<Map<String, dynamic>>> _fetchWithFallback(
    dynamic service, {
    required String doctype,
    required int limitStart,
    required List<List<String>> fieldSets,
  }) async {
    Object? lastError;
    for (final fields in fieldSets) {
      try {
        return await service.fetchReportView(
          doctype,
          fields: fields,
          limit: _pageSize,
          limitStart: limitStart,
          orderBy: 'creation desc',
        );
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? Exception('Gagal memuat $doctype');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_DashboardActivitySection>>(
      future: _future,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final sections = snapshot.data ?? _loadingSections;

        return Column(
          children: [
            SizedBox(
              height: 340,
              child: PageView.builder(
                controller: _controller,
                itemCount: sections.length,
                onPageChanged: (index) => setState(() => _page = index),
                itemBuilder: (context, index) {
                  return _DashboardActivityCard(
                    section: sections[index],
                    loading: loading,
                    loadingMore: _loadingMore.contains(sections[index].title),
                    hasMore: !_exhausted.contains(sections[index].title),
                    onLoadMore: () => _loadMore(sections[index]),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            _DashboardActivityDots(
              count: sections.length,
              activeIndex: _page.clamp(0, sections.length - 1),
            ),
          ],
        );
      },
    );
  }

  static const _loadingSections = [
    _DashboardActivitySection(
      title: 'Activity Log',
      subtitle: 'Aktivitas terbaru dari ERPNext',
      icon: Icons.history_rounded,
      color: AppColors.primary,
      rows: [],
    ),
    _DashboardActivitySection(
      title: 'Route History',
      subtitle: 'Riwayat route terbaru',
      icon: Icons.route_rounded,
      color: Color(0xFF0891B2),
      rows: [],
    ),
    _DashboardActivitySection(
      title: 'Version',
      subtitle: 'Perubahan dokumen terakhir',
      icon: Icons.restore_rounded,
      color: Color(0xFF2563EB),
      rows: [],
    ),
  ];
}

class _DashboardActivityCard extends StatelessWidget {
  const _DashboardActivityCard({
    required this.section,
    required this.loading,
    required this.loadingMore,
    required this.hasMore,
    required this.onLoadMore,
  });

  final _DashboardActivitySection section;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: section.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(section.icon, color: section.color, size: 22),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.title,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      section.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.slate,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (section.rows.isNotEmpty)
                Text(
                  '${section.rows.length} data',
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (loading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 2,
                ),
              ),
            )
          else if (section.rows.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'Belum ada data yang bisa ditampilkan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.slate,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.metrics.extentAfter < 80 && hasMore) {
                    onLoadMore();
                  }
                  return false;
                },
                child: ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  primary: false,
                  itemCount: section.rows.length + (loadingMore ? 1 : 0),
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, index) {
                    if (index >= section.rows.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      );
                    }
                    return _DashboardActivityTile(item: section.rows[index]);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DashboardActivityTile extends StatelessWidget {
  const _DashboardActivityTile({required this.item});

  final _DashboardActivityItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            item.date,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.slate,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardActivityDots extends StatelessWidget {
  const _DashboardActivityDots({
    required this.count,
    required this.activeIndex,
  });

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: List.generate(count, (index) {
      final active = index == activeIndex;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: active ? 18 : 6,
        height: 6,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary
              : AppColors.primary.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(99),
        ),
      );
    }),
  );
}

class _DashboardActivitySection {
  const _DashboardActivitySection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.rows,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<_DashboardActivityItem> rows;

  _DashboardActivitySection copyWith({List<_DashboardActivityItem>? rows}) {
    return _DashboardActivitySection(
      title: title,
      subtitle: subtitle,
      icon: icon,
      color: color,
      rows: rows ?? this.rows,
    );
  }

  Map<String, dynamic> toJson() {
    return {'title': title, 'rows': rows.map((row) => row.toJson()).toList()};
  }
}

class _DashboardActivityItem {
  const _DashboardActivityItem({
    required this.title,
    required this.subtitle,
    required this.date,
  });

  final String title;
  final String subtitle;
  final String date;

  factory _DashboardActivityItem.fromCache(Map<dynamic, dynamic> json) {
    return _DashboardActivityItem(
      title: json['title']?.toString() ?? '-',
      subtitle: json['subtitle']?.toString() ?? '-',
      date: json['date']?.toString() ?? '',
    );
  }

  factory _DashboardActivityItem.fromJson(Map<String, dynamic> json) {
    final title = _firstText(json, [
      'subject',
      'route',
      'docname',
      'reference_name',
      'name',
    ]);
    final reference = _referenceText(json);
    final owner = _firstText(json, ['owner', 'user']);
    final subtitle = [
      if (reference.isNotEmpty) reference,
      if (owner.isNotEmpty) owner,
    ].join(' | ');

    return _DashboardActivityItem(
      title: title.isEmpty ? '-' : title,
      subtitle: subtitle.isEmpty ? '-' : subtitle,
      date: _shortDate(_firstText(json, ['creation', 'modified'])),
    );
  }

  Map<String, dynamic> toJson() {
    return {'title': title, 'subtitle': subtitle, 'date': date};
  }

  static String _referenceText(Map<String, dynamic> json) {
    final doctype = _firstText(json, ['reference_doctype', 'ref_doctype']);
    final name = _firstText(json, ['reference_name', 'docname']);
    if (doctype.isEmpty) return name;
    if (name.isEmpty) return doctype;
    return '$doctype $name';
  }

  static String _firstText(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key]?.toString().trim() ?? '';
      final lower = value.toLowerCase();
      if (value.isNotEmpty &&
          lower != 'null' &&
          lower != 'none' &&
          lower != 'undefined') {
        return value;
      }
    }
    return '';
  }

  static String _shortDate(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return value.length > 10 ? value.substring(0, 10) : value;
    }
    return '${parsed.day.toString().padLeft(2, '0')}/'
        '${parsed.month.toString().padLeft(2, '0')}';
  }
}
