import '../../../data/datasources/jobs_remote_datasource.dart';

/// The message to show for an error from the Jobs API (or anything else).
String jobsErrorMessage(Object error) {
  if (error is JobsApiException) return error.detailed;
  return error.toString().replaceFirst('Exception: ', '');
}
