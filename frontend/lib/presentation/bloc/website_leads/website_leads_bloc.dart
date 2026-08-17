import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/repositories/lead_repository.dart';
import 'website_leads_event.dart';
import 'website_leads_state.dart';

class WebsiteLeadsBloc extends Bloc<WebsiteLeadsEvent, WebsiteLeadsState> {
  WebsiteLeadsBloc(this._repository) : super(const WebsiteLeadsState()) {
    on<WebsiteLeadsRequested>(_onRequested);
    on<WebsiteLeadsSearchChanged>(_onSearchChanged);
    on<WebsiteLeadDeleted>(_onDeleted);
    on<WebsiteLeadsCategoryDeleted>(_onCategoryDeleted);
  }

  final LeadRepository _repository;

  Future<void> _onRequested(
    WebsiteLeadsRequested event,
    Emitter<WebsiteLeadsState> emit,
  ) async {
    emit(state.copyWith(status: WebsiteLeadsStatus.loading, clearError: true));
    try {
      final businesses = await _repository.getWebsiteLeads();
      emit(
        state.copyWith(
          status: WebsiteLeadsStatus.success,
          businesses: businesses,
          clearError: true,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: WebsiteLeadsStatus.failure,
          error: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  void _onSearchChanged(
    WebsiteLeadsSearchChanged event,
    Emitter<WebsiteLeadsState> emit,
  ) {
    emit(state.copyWith(query: event.query));
  }

  Future<void> _onDeleted(
    WebsiteLeadDeleted event,
    Emitter<WebsiteLeadsState> emit,
  ) async {
    emit(state.copyWith(deletingLeadId: event.leadId, clearDeleteError: true));
    try {
      await _repository.deleteWebsiteLead(event.leadId);
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
    WebsiteLeadsCategoryDeleted event,
    Emitter<WebsiteLeadsState> emit,
  ) async {
    emit(state.copyWith(deletingCategory: event.category, clearCategoryDeleteMessage: true));
    try {
      final deleted = await _repository.deleteWebsiteLeadsByCategory(event.category);
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
