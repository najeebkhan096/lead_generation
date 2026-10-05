import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/outreach.dart';
import '../../domain/repositories/lead_repository.dart';

enum _Load { loading, success, failure }

enum _LeadFilter { all, notSent, sent, failed }

/// Simple outreach: save your email, pick a lead range, then validate
/// emails or analyze each business and send automatically.
class OutreachPage extends StatefulWidget {
  const OutreachPage({super.key});

  @override
  State<OutreachPage> createState() => _OutreachPageState();
}

class _OutreachPageState extends State<OutreachPage> {
  _Load _status = _Load.loading;
  String? _error;
  OutreachDashboard? _dashboard;
  List<OutreachRecord> _records = const [];
  _LeadFilter _filter = _LeadFilter.all;
  Timer? _poll;
  bool _saving = false;
  bool _starting = false;
  String _source = 'websiteLeads';

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _testInbox = TextEditingController();
  final _from = TextEditingController(text: '1');
  final _to = TextEditingController(text: '20');

  LeadRepository get _repo => context.read<LeadRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _name.dispose();
    _email.dispose();
    _testInbox.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _status = _Load.loading);
    try {
      final dashboard = await _repo.getOutreachDashboard();
      final records = await _repo.listOutreachRecords(sourceCollection: _source);
      if (!mounted) return;
      setState(() {
        _dashboard = dashboard;
        _records = records;
        _name.text = dashboard.settings.senderName;
        _email.text = dashboard.settings.senderEmail;
        _testInbox.text = dashboard.settings.testEmail;
        _status = _Load.success;
        _error = null;
      });
      _syncPoll(dashboard.job);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _status = _Load.failure;
      });
    }
  }

  void _syncPoll(OutreachJob job) {
    _poll?.cancel();
    if (!job.isRunning) return;
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refreshJob());
  }

  Future<void> _refreshJob() async {
    try {
      final job = await _repo.getOutreachJob();
      if (!mounted) return;
      setState(() => _dashboard = _dashboard?.copyWith(job: job));
      if (!job.isRunning) {
        _poll?.cancel();
        final dashboard = await _repo.getOutreachDashboard();
        final records = await _repo.listOutreachRecords(sourceCollection: _source);
        if (!mounted) return;
        setState(() {
          _dashboard = dashboard;
          _records = records;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveEmail() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the email address you send from.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final settings = await _repo.updateOutreachSettings(
        senderName: name.isEmpty ? 'Najeeb' : name,
        senderEmail: email,
        testEmail: _testInbox.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _dashboard = _dashboard?.copyWith(settings: settings);
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email saved')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _toggleTest(bool value) async {
    try {
      final settings = await _repo.updateOutreachSettings(testMode: value);
      if (!mounted) return;
      setState(() => _dashboard = _dashboard?.copyWith(settings: settings));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  (int, int)? _range() {
    final from = int.tryParse(_from.text.trim());
    final to = int.tryParse(_to.text.trim());
    if (from == null || to == null || from < 1 || to < from) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Range must be like 1 to 20.')),
      );
      return null;
    }
    if (to - from + 1 > 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at most 200 leads at a time.')),
      );
      return null;
    }
    return (from, to);
  }

  Future<void> _run(String kind) async {
    final range = _range();
    if (range == null) return;
    if (_dashboard?.job.isRunning == true) return;
    if (kind == 'send' && _email.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save your send-from email in step 1 first.')),
      );
      return;
    }
    if (kind == 'send' && _dashboard!.settings.testMode && _testInbox.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a test inbox, or turn off Send to me first.')),
      );
      return;
    }
    setState(() => _starting = true);
    try {
      if (kind == 'send') {
        await _repo.updateOutreachSettings(
          senderName: _name.text.trim().isEmpty ? 'Najeeb' : _name.text.trim(),
          senderEmail: _email.text.trim(),
          testEmail: _testInbox.text.trim(),
        );
      }
      final job = await _repo.startOutreachRun(
        kind: kind,
        from: range.$1,
        to: range.$2,
        sourceCollection: _source,
      );
      if (!mounted) return;
      setState(() {
        _dashboard = _dashboard?.copyWith(job: job);
        _starting = false;
      });
      _syncPoll(job);
    } catch (e) {
      if (!mounted) return;
      setState(() => _starting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _cancel() async {
    final job = await _repo.cancelOutreachJob();
    if (!mounted) return;
    setState(() => _dashboard = _dashboard?.copyWith(job: job));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Outreach'),
        actions: [
          IconButton(onPressed: _status == _Load.loading ? null : _load, icon: const Icon(AppIcons.refresh)),
        ],
      ),
      body: _status == _Load.loading
          ? const Center(child: CircularProgressIndicator())
          : _status == _Load.failure
              ? _ErrorPane(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Email outreach', style: Theme.of(context).textTheme.headlineSmall),
                            const SizedBox(height: 8),
                            Text(
                              'Set your email, pick which leads, then validate emails or send automatically.',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppTheme.subtle),
                            ),
                            const SizedBox(height: 24),
                            _StepCard(
                              step: '1',
                              title: 'Your email',
                              child: Column(
                                children: [
                                  TextField(
                                    controller: _name,
                                    decoration: const InputDecoration(labelText: 'Your name'),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _email,
                                    keyboardType: TextInputType.emailAddress,
                                    decoration: const InputDecoration(labelText: 'Send from this email'),
                                  ),
                                  const SizedBox(height: 12),
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Send to me first'),
                                    subtitle: const Text('Test mode — messages go to your inbox, not the lead.'),
                                    value: _dashboard!.settings.testMode,
                                    onChanged: _toggleTest,
                                  ),
                                  if (_dashboard!.settings.testMode) ...[
                                    TextField(
                                      controller: _testInbox,
                                      keyboardType: TextInputType.emailAddress,
                                      decoration: const InputDecoration(labelText: 'Test inbox'),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: FilledButton(
                                      onPressed: _saving ? null : _saveEmail,
                                      child: Text(_saving ? 'Saving…' : 'Save email'),
                                    ),
                                  ),
                                  if (!_dashboard!.settings.senderConfigured) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Add RESEND_API_KEY or SMTP_HOST in the backend .env so messages can actually send.',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.danger),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _StepCard(
                              step: '2',
                              title: 'Which leads',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  DropdownButtonFormField<String>(
                                    initialValue: _source,
                                    decoration: const InputDecoration(labelText: 'List'),
                                    items: const [
                                      DropdownMenuItem(value: 'websiteLeads', child: Text('Website leads')),
                                      DropdownMenuItem(value: 'leads', child: Text('Review leads')),
                                    ],
                                    onChanged: (v) {
                                      setState(() => _source = v ?? _source);
                                      _load();
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _source == 'websiteLeads'
                                        ? '${_dashboard!.stats.totalWebsiteLeads} website leads on file'
                                        : 'Review leads',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.faint),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _from,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                          decoration: const InputDecoration(labelText: 'From lead #'),
                                        ),
                                      ),
                                      const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 12),
                                        child: Text('to'),
                                      ),
                                      Expanded(
                                        child: TextField(
                                          controller: _to,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                          decoration: const InputDecoration(labelText: 'To lead #'),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Example: 1 to 20 sends the first 20 leads. Max 200 at a time.',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _StepCard(
                              step: '3',
                              title: 'Run',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_dashboard!.job.isRunning || _starting) ...[
                                    Text(
                                      _jobLabel(_dashboard!.job),
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    LinearProgressIndicator(value: _progress(_dashboard!.job)),
                                    const SizedBox(height: 8),
                                    Text(_jobDetail(_dashboard!.job)),
                                    const SizedBox(height: 12),
                                    OutlinedButton(onPressed: _cancel, child: const Text('Stop')),
                                  ] else ...[
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        OutlinedButton(
                                          onPressed: _starting ? null : () => _run('validate'),
                                          child: const Text('Find & validate emails'),
                                        ),
                                        FilledButton(
                                          onPressed: _starting ? null : () => _run('send'),
                                          child: const Text('Analyze & send'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Validate finds and checks emails. Analyze & send writes a message for each business and queues it automatically.',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    if (_dashboard!.job.status == 'done') ...[
                                      const SizedBox(height: 12),
                                      Text(_doneLabel(_dashboard!.job)),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                _MiniStat(label: 'Emails found', value: _dashboard!.stats.emailsFound),
                                _MiniStat(label: 'Verified', value: _dashboard!.stats.verifiedEmails),
                                _MiniStat(label: 'Sent', value: _dashboard!.stats.sent),
                                _MiniStat(label: 'Failed', value: _dashboard!.stats.failed),
                                _MiniStat(label: 'Replies', value: _dashboard!.stats.replies),
                              ],
                            ),
                            const SizedBox(height: 28),
                            Text('Each lead', style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 8),
                            Text(
                              'Whether an email was sent to that business.',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.faint),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              children: [
                                for (final f in _LeadFilter.values)
                                  ChoiceChip(
                                    label: Text(_filterLabel(f)),
                                    selected: _filter == f,
                                    onSelected: (_) => setState(() => _filter = f),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (_visibleRecords.isEmpty)
                              Text(
                                'No leads in this filter yet. Run a range above to process them.',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.faint),
                              )
                            else
                              for (final record in _visibleRecords) _LeadStatusRow(record: record),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  String _jobLabel(OutreachJob job) {
    final kind = job.kind == 'send' ? 'Sending' : 'Validating emails';
    if (job.from != null && job.to != null) return '$kind · leads ${job.from}–${job.to}';
    return kind;
  }

  double? _progress(OutreachJob job) {
    if (job.total <= 0) return null;
    return (job.processed / job.total).clamp(0, 1);
  }

  String _jobDetail(OutreachJob job) {
    final current = job.currentBusiness;
    final parts = <String>[
      '${job.processed} of ${job.total}',
      if (job.emailsFound > 0) '${job.emailsFound} emails found',
      if (job.verified > 0) '${job.verified} verified',
      if (job.queued > 0) '${job.queued} queued',
      if (job.failed > 0) '${job.failed} failed',
    ];
    if (current != null) parts.add(current);
    return parts.join('  ·  ');
  }

  String _doneLabel(OutreachJob job) {
    final kind = job.kind == 'send' ? 'Send finished' : 'Validation finished';
    return '$kind — ${job.processed} processed, ${job.emailsFound} emails found, ${job.verified} verified, ${job.queued} queued, ${job.failed} failed.';
  }

  List<OutreachRecord> get _visibleRecords {
    return _records.where((r) {
      return switch (_filter) {
        _LeadFilter.all => true,
        _LeadFilter.sent => r.outreachStatus.wasSent,
        _LeadFilter.failed =>
          r.outreachStatus == OutreachStatus.failed ||
              r.outreachStatus == OutreachStatus.bounced ||
              r.outreachStatus == OutreachStatus.emailInvalid,
        _LeadFilter.notSent => !r.outreachStatus.wasSent &&
            r.outreachStatus != OutreachStatus.queued &&
            r.outreachStatus != OutreachStatus.failed &&
            r.outreachStatus != OutreachStatus.bounced,
      };
    }).toList();
  }

  String _filterLabel(_LeadFilter filter) {
    final count = _records.where((r) {
      return switch (filter) {
        _LeadFilter.all => true,
        _LeadFilter.sent => r.outreachStatus.wasSent,
        _LeadFilter.failed =>
          r.outreachStatus == OutreachStatus.failed ||
              r.outreachStatus == OutreachStatus.bounced ||
              r.outreachStatus == OutreachStatus.emailInvalid,
        _LeadFilter.notSent => !r.outreachStatus.wasSent &&
            r.outreachStatus != OutreachStatus.queued &&
            r.outreachStatus != OutreachStatus.failed &&
            r.outreachStatus != OutreachStatus.bounced,
      };
    }).length;
    return switch (filter) {
      _LeadFilter.all => 'All ($count)',
      _LeadFilter.notSent => 'Not sent ($count)',
      _LeadFilter.sent => 'Sent ($count)',
      _LeadFilter.failed => 'Failed ($count)',
    };
  }
}

class _LeadStatusRow extends StatelessWidget {
  const _LeadStatusRow({required this.record});
  final OutreachRecord record;

  @override
  Widget build(BuildContext context) {
    final status = record.outreachStatus;
    final sent = status.wasSent;
    final failed = status == OutreachStatus.failed ||
        status == OutreachStatus.bounced ||
        status == OutreachStatus.emailInvalid;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.business, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  record.email ?? 'No email',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (record.lastError != null && failed) ...[
                  const SizedBox(height: 2),
                  Text(record.lastError!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: sent
                  ? AppTheme.sage100
                  : failed
                      ? AppTheme.accent100
                      : AppTheme.neutral100,
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            ),
            child: Text(
              status.label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: sent
                    ? AppTheme.sage800
                    : failed
                        ? AppTheme.accent800
                        : AppTheme.neutral700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.step, required this.title, required this.child});
  final String step;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppTheme.accent100,
                child: Text(step, style: const TextStyle(color: AppTheme.accent800, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: Theme.of(context).textTheme.headlineSmall),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.alert, color: AppTheme.danger, size: 36),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
