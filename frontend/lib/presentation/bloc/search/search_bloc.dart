import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/repositories/lead_repository.dart';
import 'search_event.dart';
import 'search_state.dart';

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  SearchBloc(this._repository) : super(const SearchState()) {
    on<SearchSubmitted>(_onSubmitted);
    on<SearchCleared>(_onCleared);
    on<ExportCsvRequested>(_onExportCsv);
    on<ExportJsonRequested>(_onExportJson);
    on<SaveToDatabaseRequested>(_onSaveToDatabase);
  }

  final LeadRepository _repository;

  /// Last exported payload for web download helper.
  String? lastExportContent;
  String? lastExportFilename;

  Future<void> _onSubmitted(
    SearchSubmitted event,
    Emitter<SearchState> emit,
  ) async {
    emit(
      state.copyWith(
        status: SearchStatus.loading,
        location: event.location,
        category: event.category,
        dateRange: event.dateRange,
        progressMessage: 'Starting search…',
        clearError: true,
        clearExport: true,
      ),
    );

    try {
      final leads = await _repository.searchLeads(
        location: event.location,
        category: event.category,
        dateRange: event.dateRange,
        nationwide: event.nationwide,
        targetLeadCount: event.targetLeadCount,
        analyze: event.analyze,
        onProgress: (message) {
          emit(
            state.copyWith(
              status: SearchStatus.loading,
              progressMessage: message,
            ),
          );
        },
      );
      emit(
        state.copyWith(
          status: SearchStatus.success,
          leads: leads,
          clearError: true,
          clearProgress: true,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: SearchStatus.failure,
          error: e.toString().replaceFirst('Exception: ', ''),
          clearProgress: true,
        ),
      );
    }
  }

  void _onCleared(SearchCleared event, Emitter<SearchState> emit) {
    lastExportContent = null;
    lastExportFilename = null;
    emit(const SearchState());
  }

  Future<void> _onExportCsv(
    ExportCsvRequested event,
    Emitter<SearchState> emit,
  ) async {
    try {
      final csv = await _repository.exportCsv();
      lastExportContent = csv;
      lastExportFilename = 'leads.csv';
      emit(state.copyWith(exportMessage: 'CSV ready (${state.leads.length} leads)'));
    } catch (e) {
      emit(
        state.copyWith(
          exportMessage: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  Future<void> _onExportJson(
    ExportJsonRequested event,
    Emitter<SearchState> emit,
  ) async {
    try {
      final json = await _repository.exportJson();
      lastExportContent = json;
      lastExportFilename = 'leads.json';
      emit(state.copyWith(exportMessage: 'JSON ready (${state.leads.length} leads)'));
    } catch (e) {
      emit(
        state.copyWith(
          exportMessage: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  Future<void> _onSaveToDatabase(
    SaveToDatabaseRequested event,
    Emitter<SearchState> emit,
  ) async {
    if (state.leads.isEmpty) {
      emit(state.copyWith(saveMessage: 'No leads to save.'));
      return;
    }
    emit(state.copyWith(savingToDb: true, clearSave: true));
    try {
      final message = await _repository.saveToDatabase();
      emit(state.copyWith(savingToDb: false, saveMessage: message));
    } catch (e) {
      emit(
        state.copyWith(
          savingToDb: false,
          saveMessage: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }
}
