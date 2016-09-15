package SL::Controller::PartsClassification;

use strict;

use parent qw(SL::Controller::Base);

use SL::DB::PartsClassification;
use SL::Helper::Flash;

use Rose::Object::MakeMethods::Generic
(
 scalar => [ qw(parts_classification) ],
);

__PACKAGE__->run_before('check_auth');
__PACKAGE__->run_before('load_parts_classification', only => [ qw(edit update destroy) ]);

#
# This Controller is responsible for creating,editing or deleting
# Part Classifications.
#
# The use of Part Classifications is described in SL::DB::PartsClassification
# 
#

# List all available part classifications
#

sub action_list {
  my ($self) = @_;

  $self->render('parts_classification/list',
                title         => $::locale->text('Parts Classifications'),
                PARTS_CLASSIFICATIONS => SL::DB::Manager::PartsClassification->get_all_sorted);
}

# A Form for a new creatable part classifications is generated
#
sub action_new {
  my ($self) = @_;

  $self->{parts_classification} = SL::DB::PartsClassification->new;
  $self->render('parts_classification/form', title => $::locale->text('Create a new parts classification'));
}

# Edit an existing part classifications
#
sub action_edit {
  my ($self) = @_;
  $self->render('parts_classification/form', title => $::locale->text('Edit parts classification'));
}

# A new part classification is saved
#
sub action_create {
  my ($self) = @_;

  $self->{parts_classification} = SL::DB::PartsClassification->new;
  $self->create_or_update;
}

# An existing part classification is saved
#
sub action_update {
  my ($self) = @_;
  $self->create_or_update;
}

# An existing part classification is deleted
#
# The basic classifications cannot be deleted, also classifications which are in use
#
sub action_destroy {
  my ($self) = @_;

  if ( $self->{parts_classification}->id < 5 ) {
    flash_later('error', $::locale->text('The basic parts classification cannot be deleted.'));
  }
  elsif (eval { $self->{parts_classification}->delete; 1; }) {
    flash_later('info',  $::locale->text('The parts classification has been deleted.'));
  } else {
    flash_later('error', $::locale->text('The parts classification is in use and cannot be deleted.'));
  }

  $self->redirect_to(action => 'list');
}
# reordering the lines
#
sub action_reorder {
  my ($self) = @_;

  SL::DB::PartsClassification->reorder_list(@{ $::form->{parts_classification_id} || [] });

  $self->render(\'', { type => 'json' });
}

#
# filters
#

# check authentication, only "config" is allowed
#
sub check_auth {
  $::auth->assert('config');
}

#
# helpers
#

# submethod for update the database
#
sub create_or_update {
  my $self   = shift;
  my $is_new = !$self->{parts_classification}->id;
  my $params = delete($::form->{parts_classification}) || { };

  $self->{parts_classification}->assign_attributes(%{ $params });

  my @errors = $self->{parts_classification}->validate;

  if (@errors) {
    flash('error', @errors);
    $self->render('parts_classification/form', title => $is_new ? $::locale->text('Create a new parts classification') : $::locale->text('Edit parts classification'));
    return;
  }

  $self->{parts_classification}->save;

  flash_later('info', $is_new ? $::locale->text('The parts classification has been created.') : $::locale->text('The parts classification has been saved.'));
  $self->redirect_to(action => 'list');
}

# submethod for loading one item from the database
#
sub load_parts_classification {
  my ($self) = @_;
  $self->{parts_classification} = SL::DB::PartsClassification->new(id => $::form->{id})->load;
}

1;



__END__

=encoding utf-8

=head1 NAME

SL::Controller::PartsClassification

=head1 SYNOPSIS

This Controller is responsible for creating,editing or deleting
Part Classifications.

The use of Part Classifications is described in L<SL::DB::PartsClassification>

=head1 METHODS

=head2 action_create

 $self->action_create();

A new part classification is saved



=head2 action_destroy

 $self->action_destroy();

An existing part classification is deleted

The basic classifications cannot be deleted, also classifications which are in use



=head2 action_edit

 $self->action_edit();

Edit an existing part classifications



=head2 action_list

 $self->action_list();

List all available part classifications



=head2 action_new

 $self->action_new();

A Form for a new creatable part classifications is generated



=head2 action_reorder

 $self->action_reorder();

reordering the lines



=head2 action_update

 $self->action_update();

An existing part classification is saved



=head2 check_auth

 $self->check_auth();

check authentication, only "config" is allowed



=head2 create_or_update

 $self->create_or_update();

submethod for update the database



=head2 load_parts_classification

 $self->load_parts_classification();

submethod for loading one item from the database


=head1 BUGS

=head1 AUTHOR

Martin Helmling E<lt>martin.helmling@opendynamic.deE<gt>

=cut

