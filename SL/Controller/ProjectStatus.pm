package SL::Controller::ProjectStatus;

use strict;

use parent qw(SL::Controller::Base);

use SL::DB::ProjectStatus;
use SL::Helper::Flash;

use Rose::Object::MakeMethods::Generic
(
 scalar => [ qw(project_status) ],
);

__PACKAGE__->run_before('check_auth');
__PACKAGE__->run_before('load_project_status', only => [ qw(edit update destroy) ]);

#
# actions
#

sub action_list {
  my ($self) = @_;

  $self->setup_list_action_bar;
  $self->render('project_status/list',
                title          => $::locale->text('Project Status'),
                PROJECT_STATUS => SL::DB::Manager::ProjectStatus->get_all_sorted);
}

sub action_new {
  my ($self) = @_;

  $self->{project_status} = SL::DB::ProjectStatus->new;
  $self->render_form(title => $::locale->text('Create a new project status'));
}

sub action_edit {
  my ($self) = @_;
  $self->render_form(title => $::locale->text('Edit project status'));
}

sub action_create {
  my ($self) = @_;

  $self->{project_status} = SL::DB::ProjectStatus->new;
  $self->create_or_update;
}

sub action_update {
  my ($self) = @_;
  $self->create_or_update;
}

sub action_destroy {
  my ($self) = @_;

  if (eval { $self->{project_status}->delete; 1; }) {
    flash_later('info',  $::locale->text('The project status has been deleted.'));
  } else {
    flash_later('error', $::locale->text('The project status is in use and cannot be deleted.'));
  }

  $self->redirect_to(action => 'list');
}

sub action_reorder {
  my ($self) = @_;

  SL::DB::ProjectStatus->reorder_list(@{ $::form->{project_status_id} || [] });

  $self->render(\'', { type => 'json' });
}

#
# filters
#

sub check_auth {
  $::auth->assert('config');
}

#
# helpers
#

sub create_or_update {
  my $self   = shift;
  my $is_new = !$self->{project_status}->id;
  my $params = delete($::form->{project_status}) || { };

  $self->{project_status}->assign_attributes(%{ $params });

  my @errors = $self->{project_status}->validate;

  if (@errors) {
    flash('error', @errors);
    $self->render_form(title => $is_new ? $::locale->text('Create a new project status') : $::locale->text('Edit project status'));
    return;
  }

  $self->{project_status}->save;

  flash_later('info', $is_new ? $::locale->text('The project status has been created.') : $::locale->text('The project status has been saved.'));
  $self->redirect_to(action => 'list');
}

sub load_project_status {
  my ($self) = @_;
  $self->{project_status} = SL::DB::ProjectStatus->new(id => $::form->{id})->load;
}

sub render_form {
  my ($self, %params) = @_;

  $self->setup_form_action_bar;
  $self->render('project_status/form', %params);
}

sub setup_form_action_bar {
  my ($self) = @_;

  my $is_new = !$self->{project_status}->id;

  for my $bar ($::request->layout->get('actionbar')) {
    $bar->add(
      action => [
        $::locale->text('Save'),
        submit    => [ '#form', { action => 'ProjectStatus/' . ($is_new ? 'create' : 'update') } ],
        accesskey => 'enter',
      ],
      action => [
        $::locale->text('Delete'),
        submit   => [ '#form', { action => 'ProjectStatus/destroy' } ],
        confirm  => $::locale->text('Do you really want to delete this object?'),
        disabled => $is_new ? $::locale->text('This object has not been saved yet.') : undef,
      ],

      link => [
        $::locale->text('Abort'),
        link => $self->url_for(action => 'list'),
      ],
    );
  }
}

sub setup_list_action_bar {
  my ($self) = @_;

  for my $bar ($::request->layout->get('actionbar')) {
    $bar->add(
      link => [
        $::locale->text('Add'),
        link => $self->url_for(action => 'new'),
      ],
    );
  }
}

1;
