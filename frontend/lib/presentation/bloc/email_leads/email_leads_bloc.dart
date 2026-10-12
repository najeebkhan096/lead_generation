import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/repositories/lead_repository.dart';
import 'email_leads_event.dart';
import 'email_leads_state.dart';

class EmailLeadsBloc extends Bloc<EmailLeadsEvent, EmailLeadsState> {
  EmailLeadsBloc(this._repository) : super(const EmailLeadsState()) {
    on<EmailLeadsRequested>(_onRequested);
    on<EmailLeadsSearchChanged>(_onSearchChanged);
    on<EmailLeadDeleted>(_onDeleted);
    on<EmailLeadsCategoryDeleted>(_onCategoryDeleted);
  }

  final LeadRepository _repository;

  Future<void> _onRequested(
    EmailLeadsRequested event,
    Emitter<EmailLeadsState> emit,
  ) async {
    emit(state.copyWith(status: EmailLeadsStatus.loading, clearError: true));
    try {
      final businesses = await _repository.getEmailLeads();
      emit(
        state.copyWith(
          status: EmailLeadsStatus.success,
          businesses: businesses,
          clearError: true,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: EmailLeadsStatus.failure,
          error: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  void _onSearchChanged(
    EmailLeadsSearchChanged event,
    Emitter<EmailLeadsState> emit,
  ) {
    emit(state.copyWith(query: event.query));
  }

  Future<void> _onDeleted(
    EmailLeadDeleted event,
    Emitter<EmailLeadsState> emit,
  ) async {
    emit(state.copyWith(deletingLeadId: event.leadId, clearDeleteError: true));
    try {
      await _repository.deleteEmailLead(event.leadId);
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
    EmailLeadsCategoryDeleted event,
    Emitter<EmailLeadsState> emit,
  ) async {
    emit(state.copyWith(deletingCategory: event.category, clearCategoryDeleteMessage: true));
    try {
      final deleted = await _repository.deleteEmailLeadsByCategory(event.category);
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
