import 'package:equatable/equatable.dart';

abstract class EmailLeadsEvent extends Equatable {
  const EmailLeadsEvent();

  @override
  List<Object?> get props => [];
}

class EmailLeadsRequested extends EmailLeadsEvent {
  const EmailLeadsRequested();
}

class EmailLeadsSearchChanged extends EmailLeadsEvent {
  const EmailLeadsSearchChanged(this.query);

  final String query;

  @override
  List<Object?> get props => [query];
}

/// Deletes a single email lead ([Lead.dbId]) from Firestore and removes it
/// from the list on success.
class EmailLeadDeleted extends EmailLeadsEvent {
  const EmailLeadDeleted(this.leadId);

  final String leadId;

  @override
  List<Object?> get props => [leadId];
}

/// Deletes every email lead in an exact category and removes them all from
/// the list on success.
class EmailLeadsCategoryDeleted extends EmailLeadsEvent {
  const EmailLeadsCategoryDeleted(this.category);

  final String category;

  @override
  List<Object?> get props => [category];
}
