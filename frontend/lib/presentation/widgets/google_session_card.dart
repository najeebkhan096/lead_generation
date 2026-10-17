import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/maps_session_status.dart';
import '../../domain/repositories/lead_repository.dart';

/// Whether a scan may start for this Google sign-in state. Only states that
/// are certainly signed out block it; if the backend cannot tell ("unknown",
/// an error) it makes the call itself when the scan starts.
bool googleSessionBlocksScan(MapsSessionStatus? s) =>
    s != null && (s.status == 'signed_out' || s.status == 'no_profile');

/// The scraper's Google sign-in, on the scan page.
///
/// Google shows anonymous visitors only a few reviews and will not let them
/// sort, so a scan without a signed-in Google account misses most 1-star
/// reviews. "Sign in to Google" opens a window on the computer running the
/// backend: you sign in there by hand (the app never sees your password) and
/// close it.
class GoogleSessionCard extends StatefulWidget {
  const GoogleSessionCard({super.key, this.onStatus});

  /// Called whenever the status is read, so the page can enable/disable Start.
  final ValueChanged<MapsSessionStatus>? onStatus;

  @override
  State<GoogleSessionCard> createState() => _GoogleSessionCardState();
}

class _GoogleSessionCardState extends State<GoogleSessionCard> {
  MapsSessionStatus? _status;
  String? _error;
  bool _busy = true;
  Timer? _poll;

  LeadRepository get _repo => context.read<LeadRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = await _repo.getMapsSessionStatus(refresh: refresh);
      if (!mounted) return;
      setState(() {
        _status = s;
        _busy = false;
      });
      widget.onStatus?.call(s);
      _syncPolling(s);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// While the sign-in window is open, keep asking until it is closed and the
  /// backend has re-checked the session.
  void _syncPolling(MapsSessionStatus s) {
    final waiting = s.loginInProgress;
    if (waiting && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 3), (_) async {
        try {
          final next = await _repo.getMapsSessionStatus();
          if (!mounted) return;
          setState(() => _status = next);
          widget.onStatus?.call(next);
          if (!next.loginInProgress) {
            _poll?.cancel();
            _poll = null;
          }
        } catch (_) {
          // keep polling
        }
      });
    } else if (!waiting) {
      _poll?.cancel();
      _poll = null;
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repo.startMapsLogin();
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final signedIn = s?.signedIn == true;
    final waiting = s?.loginInProgress == true;
    final inUse = s?.inUseByScan == true;
    final blocking = googleSessionBlocksScan(s);

    final Color tint = signedIn || inUse
        ? AppTheme.sage100
        : waiting
            ? AppTheme.accent100
            : blocking
                ? const Color(0xFFFDE8E8)
                : AppTheme.neutral100;
    final Color ink = signedIn || inUse ? AppTheme.sage700 : blocking ? AppTheme.danger : AppTheme.neutral700;
    final IconData icon = signedIn || inUse ? AppIcons.shieldCheck : waiting ? AppIcons.clock : AppIcons.alert;

    final String title;
    final String body;
    if (_status == null && _busy) {
      title = 'Checking Google sign-in…';
      body = 'Opening a browser in the background to see if the saved account is signed in.';
    } else if (_status == null) {
      title = 'Could not check the Google sign-in';
      body = _error ?? 'Is the backend running?';
    } else if (waiting) {
      title = 'Sign in in the Google window';
      body = 'A Chrome window opened on the computer running the backend. Sign in there with the Google account to use. The window closes by itself once you are signed in, and this page updates on its own.';
    } else if (inUse) {
      title = 'A scan is using the Google account';
      body = 'To sign in again, stop the scan first.';
    } else if (signedIn) {
      title = 'Signed in to Google';
      body = 'Scans can sort reviews and read every 1-star review inside the date window.';
    } else if (s!.status == 'signed_out') {
      title = 'Google sign-in has expired';
      body = 'Sign in again before scanning, otherwise Google hides most reviews and 1-star reviews are missed.';
    } else if (s.status == 'no_profile') {
      title = 'Sign in to Google to scan';
      body = 'Google shows anonymous visitors only a few reviews and will not let them sort, so 1-star reviews would be missed. Sign in once with a dedicated Google account (not your personal one); it is remembered.';
    } else if (s.status == 'locked') {
      title = 'The Google profile is busy';
      body = 'It is open in another browser window. Close that window and check again.';
    } else {
      title = 'Google sign-in could not be confirmed';
      body = s.detail.isNotEmpty ? s.detail : 'The scan will check again when it starts and refuses to run if you are signed out.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: ink.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_busy || waiting)
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2)),
                )
              else
                Icon(icon, size: 20, color: ink),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: ink)),
                    const SizedBox(height: 4),
                    Text(body, style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppTheme.neutral700)),
                    if (_error != null && _status != null) ...[
                      const SizedBox(height: 6),
                      Text(_error!, style: const TextStyle(fontSize: 12, color: AppTheme.danger)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (!waiting && !inUse) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!signedIn)
                  FilledButton.icon(
                    onPressed: _busy ? null : _signIn,
                    icon: const Icon(AppIcons.logIn, size: 16),
                    label: const Text('Sign in to Google'),
                  ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _load(refresh: true),
                  icon: const Icon(AppIcons.refresh, size: 16),
                  label: Text(signedIn ? 'Check again' : 'I signed in, check'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
