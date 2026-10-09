import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/sale.dart';
import '../../domain/entities/watchlist_entry.dart';
import '../../domain/repositories/lead_repository.dart';

const scanWindowDays = 28;

/// Scans the Google Maps page of every client business (each once) for 1-star
/// reviews from the last [scanWindowDays] days and lists them with links.
/// The scan loads each Maps page in turn, so it can take a while.
class ClientReviewScanPage extends StatefulWidget {
  const ClientReviewScanPage({super.key});

  @override
  State<ClientReviewScanPage> createState() => _ClientReviewScanPageState();
}

class _ClientReviewScanPageState extends State<ClientReviewScanPage> {
  List<SaleReviewScanResult>? _results;
  String? _error;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final results = await context.read<LeadRepository>().scanSaleReviews(
            dateRange: '$scanWindowDays',
            dedupe: true,
          );
      if (!mounted) return;
      setState(() {
        _results = results;
        _scanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _scanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('1★ review scan'),
        actions: [
          IconButton(
            tooltip: 'Scan again',
            onPressed: _scanning ? null : _scan,
            icon: const Icon(AppIcons.refresh),
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_scanning) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Scanning every client\'s Google Maps page…', textAlign: TextAlign.center),
            SizedBox(height: 6),
            Text(
              'Looking for 1★ reviews from the last $scanWindowDays days. Each business is loaded one by one, so this can take several minutes. Keep this page open.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.subtle, fontSize: 12.5),
            ),
          ]),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.danger)),
            const SizedBox(height: 16),
            OutlinedButton.icon(onPressed: _scan, icon: const Icon(AppIcons.refresh, size: 18), label: const Text('Try again')),
          ]),
        ),
      );
    }
    final results = _results ?? const <SaleReviewScanResult>[];
    final flagged = results.where((r) => r.newReviews.isNotEmpty).toList();
    final notScanned = results.where((r) => r.skipped || r.error != null).toList();
    final clean = results.length - flagged.length - notScanned.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(
          flagged.isEmpty
              ? 'No 1★ reviews in the last $scanWindowDays days'
              : '${flagged.length} client${flagged.length == 1 ? '' : 's'} with 1★ reviews in the last $scanWindowDays days',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          '${results.length} clients checked · $clean clean · ${notScanned.length} not scanned',
          style: const TextStyle(color: AppTheme.subtle, fontSize: 12.5),
        ),
        const SizedBox(height: 16),
        for (final r in flagged) _FlaggedClientCard(result: r),
        if (notScanned.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Not scanned (${notScanned.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
              children: [
                for (final r in notScanned)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(r.name ?? 'Unnamed business'),
                    subtitle: Text(r.error ?? 'Not scanned'),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FlaggedClientCard extends StatelessWidget {
  const _FlaggedClientCard({required this.result});

  final SaleReviewScanResult result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(r.name ?? 'Unnamed business', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            if (r.rating != null) ...[
              const Icon(AppIcons.star, size: 14, color: AppTheme.accent700),
              const SizedBox(width: 3),
              Text(r.rating!.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
            if (r.url.isNotEmpty)
              IconButton(
                tooltip: 'Open business page',
                onPressed: () => launchUrl(Uri.parse(r.url), mode: LaunchMode.externalApplication),
                icon: const Icon(AppIcons.mapPin, size: 18, color: AppTheme.accent700),
              ),
          ]),
          const SizedBox(height: 4),
          for (final review in r.newReviews) _ReviewRow(review: review, fallbackUrl: r.url),
        ]),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.review, required this.fallbackUrl});

  final WatchlistReview review;
  final String fallbackUrl;

  @override
  Widget build(BuildContext context) {
    final link = review.link ?? (fallbackUrl.isEmpty ? null : fallbackUrl);
    return InkWell(
      onTap: link == null ? null : () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(AppIcons.star, size: 15, color: AppTheme.accent700),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '${review.reviewer} · ${review.stars ?? 1}★ · ${review.date}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.subtle),
              ),
              if (review.text.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(review.text),
              ],
              if (link != null) ...[
                const SizedBox(height: 4),
                const Text(
                  'Open review',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accent700,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
