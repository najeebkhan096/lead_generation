import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/domain/entities/outreach.dart';

void main() {
  test('OutreachStatus round-trips JSON used by the backend', () {
    expect(OutreachStatus.fromJson('ready_for_review'), OutreachStatus.readyForReview);
    expect(OutreachStatus.notInterested.json, 'not_interested');
    expect(OutreachStatus.sent.label, 'Sent');
    expect(OutreachStatus.sent.wasSent, isTrue);
    expect(OutreachStatus.notProcessed.sendLabel, 'Not sent');
    expect(OutreachStatus.queued.sendLabel, 'Sending');
    expect(OutreachStatus.unsubscribed.label, 'Unsubscribed');
  });

  test('OutreachRecord.fromJson reads a website-lead pipeline document', () {
    final record = OutreachRecord.fromJson({
      'id': 'websiteLeads_abc',
      'sourceCollection': 'websiteLeads',
      'sourceLeadId': 'abc',
      'business': 'ABC Restaurant',
      'email': 'info@abc.com',
      'emailVerified': true,
      'outreachStatus': 'ready_for_review',
      'websiteAnalysis': {
        'score': 72,
        'issues': [
          {'title': 'No clear online booking option', 'description': 'Homepage has no book/order wording.'},
        ],
        'opportunities': [],
      },
      'generatedSubject': "A quick idea for ABC Restaurant's website",
      'unsubscribeStatus': false,
    });
    expect(record.business, 'ABC Restaurant');
    expect(record.emailVerified, isTrue);
    expect(record.websiteAnalysis!.score, 72);
    expect(record.websiteAnalysis!.issues.single.title, contains('booking'));
    expect(record.outreachStatus, OutreachStatus.readyForReview);
  });

  test('OutreachJob.fromJson reads a running range job', () {
    final job = OutreachJob.fromJson({
      'status': 'running',
      'kind': 'send',
      'from': 1,
      'to': 20,
      'total': 20,
      'processed': 4,
      'emailsFound': 2,
      'verified': 1,
      'queued': 1,
      'current': {'id': 'abc', 'business': 'ABC Restaurant'},
    });
    expect(job.isRunning, isTrue);
    expect(job.kind, 'send');
    expect(job.currentBusiness, 'ABC Restaurant');
    expect(job.processed, 4);
  });
}
