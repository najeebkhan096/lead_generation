import 'package:equatable/equatable.dart';

import '../../../domain/entities/lead_page.dart';

abstract class PagedLeadsEvent extends Equatable {
  const PagedLeadsEvent();

  @override
  List<Object?> get props => [];
}

/// First load: page one plus the category list.
class PagedLeadsStarted extends PagedLeadsEvent {
  const PagedLeadsStarted();
}

/// Reload page one with the current filters (pull-to-refresh, or after a
/// validation run changed the data).
class PagedLeadsRefreshed extends PagedLeadsEvent {
  const PagedLeadsRefreshed();
}

/// The list scrolled near its end — fetch the next page.
class PagedLeadsLoadMore extends PagedLeadsEvent {
  const PagedLeadsLoadMore();
}

/// The search box changed. Debounced — the server is only asked once the
/// user pauses typing.
class PagedLeadsQueryChanged extends PagedLeadsEvent {
  const PagedLeadsQueryChanged(this.query);

  final String query;

  @override
  List<Object?> get props => [query];
}

/// `null` = all categories.
class PagedLeadsCategoryChanged extends PagedLeadsEvent {
  const PagedLeadsCategoryChanged(this.category);

  final String? category;

  @override
  List<Object?> get props => [category];
}

/// Collection-specific narrowing: review leads' WhatsApp-verified toggle,
/// website leads' has-email toggle, WhatsApp leads' source signal.
class PagedLeadsFilterChanged extends PagedLeadsEvent {
  const PagedLeadsFilterChanged({this.verifiedOnly, this.emailOnly, this.sourceType, this.clearSourceType = false});

  final bool? verifiedOnly;
  final bool? emailOnly;
  final String? sourceType;
  final bool clearSourceType;

  @override
  List<Object?> get props => [verifiedOnly, emailOnly, sourceType, clearSourceType];
}

/// Deletes one lead by [Lead.dbId] and removes it from the list.
class PagedLeadDeleted extends PagedLeadsEvent {
  const PagedLeadDeleted(this.leadId);

  final String leadId;

  @override
  List<Object?> get props => [leadId];
}

/// Deletes every lead of an exact category, then reloads.
class PagedLeadsCategoryDeleted extends PagedLeadsEvent {
  const PagedLeadsCategoryDeleted(this.category);

  final String category;

  @override
  List<Object?> get props => [category];
}

/// Internal: the debounce timer fired.
class PagedLeadsQueryCommitted extends PagedLeadsEvent {
  const PagedLeadsQueryCommitted();
}

/// Internal: the category list arrived.
class PagedLeadsCategoriesLoaded extends PagedLeadsEvent {
  const PagedLeadsCategoriesLoaded(this.categories);

  final List<LeadCategory> categories;

  @override
  List<Object?> get props => [categories];
}
