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
