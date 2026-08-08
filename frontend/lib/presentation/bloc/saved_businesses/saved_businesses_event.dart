import 'package:equatable/equatable.dart';

abstract class SavedBusinessesEvent extends Equatable {
  const SavedBusinessesEvent();

  @override
  List<Object?> get props => [];
}

class SavedBusinessesRequested extends SavedBusinessesEvent {
  const SavedBusinessesRequested();
}

class SavedBusinessesSearchChanged extends SavedBusinessesEvent {
  const SavedBusinessesSearchChanged(this.query);

  final String query;

  @override
  List<Object?> get props => [query];
}

/// Deletes a single saved lead ([Lead.dbId]) from Firestore and removes it
/// from the list on success.
class SavedBusinessDeleted extends SavedBusinessesEvent {
  const SavedBusinessDeleted(this.leadId);

  final String leadId;

  @override
  List<Object?> get props => [leadId];
}

/// Deletes every saved lead in an exact category and removes them all from
/// the list on success.
class SavedCategoryDeleted extends SavedBusinessesEvent {
  const SavedCategoryDeleted(this.category);

  final String category;

  @override
  List<Object?> get props => [category];
}
