import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/repositories/lead_repository.dart';
import 'saved_businesses_event.dart';
import 'saved_businesses_state.dart';

class SavedBusinessesBloc extends Bloc<SavedBusinessesEvent, SavedBusinessesState> {
  SavedBusinessesBloc(this._repository) : super(const SavedBusinessesState()) {
    on<SavedBusinessesRequested>(_onRequested);
    on<SavedBusinessesSearchChanged>(_onSearchChanged);
    on<SavedBusinessDeleted>(_onDeleted);
    on<SavedCategoryDeleted>(_onCategoryDeleted);
  }

  final LeadRepository _repository;

  Future<void> _onRequested(
    SavedBusinessesRequested event,
    Emitter<SavedBusinessesState> emit,
  ) async {
    emit(state.copyWith(status: SavedBusinessesStatus.loading, clearError: true));
    try {
      final businesses = await _repository.getSavedBusinesses();
      emit(
        state.copyWith(
          status: SavedBusinessesStatus.success,
          businesses: businesses,
          clearError: true,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: SavedBusinessesStatus.failure,
          error: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  void _onSearchChanged(
    SavedBusinessesSearchChanged event,
    Emitter<SavedBusinessesState> emit,
  ) {
    emit(state.copyWith(query: event.query));
  }

  Future<void> _onDeleted(
    SavedBusinessDeleted event,
    Emitter<SavedBusinessesState> emit,
  ) async {
    emit(state.copyWith(deletingLeadId: event.leadId, clearDeleteError: true));
    try {
      await _repository.deleteLead(event.leadId);
      emit(
        state.copyWith(
          businesses: state.businesses.where((b) => b.dbId != event.leadId).toList(),
          clearDeletingLeadId: true,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          clearDeletingLeadId: true,
          deleteError: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  Future<void> _onCategoryDeleted(
    SavedCategoryDeleted event,
    Emitter<SavedBusinessesState> emit,
  ) async {
    emit(state.copyWith(deletingCategory: event.category, clearCategoryDeleteMessage: true));
    try {
      final deleted = await _repository.deleteLeadsByCategory(event.category);
      emit(
        state.copyWith(
          businesses: state.businesses.where((b) => b.category != event.category).toList(),
          clearDeletingCategory: true,
          categoryDeleteMessage: 'Deleted $deleted lead${deleted == 1 ? '' : 's'} in "${event.category}".',
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          clearDeletingCategory: true,
          categoryDeleteMessage: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }
}
