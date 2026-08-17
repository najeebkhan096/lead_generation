import 'package:equatable/equatable.dart';

abstract class WebsiteLeadsEvent extends Equatable {
  const WebsiteLeadsEvent();

  @override
  List<Object?> get props => [];
}

class WebsiteLeadsRequested extends WebsiteLeadsEvent {
  const WebsiteLeadsRequested();
}

class WebsiteLeadsSearchChanged extends WebsiteLeadsEvent {
  const WebsiteLeadsSearchChanged(this.query);

  final String query;

  @override
  List<Object?> get props => [query];
}

/// Deletes a single website lead ([Lead.dbId]) from Firestore and removes
/// it from the list on success.
class WebsiteLeadDeleted extends WebsiteLeadsEvent {
  const WebsiteLeadDeleted(this.leadId);

  final String leadId;

  @override
  List<Object?> get props => [leadId];
}

/// Deletes every website lead in an exact category and removes them all
/// from the list on success.
class WebsiteLeadsCategoryDeleted extends WebsiteLeadsEvent {
  const WebsiteLeadsCategoryDeleted(this.category);

  final String category;

  @override
  List<Object?> get props => [category];
}
