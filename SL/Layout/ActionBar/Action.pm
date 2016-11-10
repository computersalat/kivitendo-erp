package SL::Layout::ActionBar::Action;

use strict;
use parent qw(Rose::Object);

use SL::Presenter;

use Rose::Object::MakeMethods::Generic (
  'scalar --get_set_init' => [ qw(id params text) ],
);

# subclassing interface

sub render {
  die 'needs to be implemented';
}

sub script {
  sprintf q|$('#%s').data('action', %s);|, $_[0]->id, JSON->new->allow_blessed->convert_blessed->encode($_[0]->params);
}

# static constructors

sub from_descriptor {
  my ($class, $descriptor) = @_;
  require SL::Layout::ActionBar::Separator;
  require SL::Layout::ActionBar::ComboBox;

  return {
     separator => SL::Layout::ActionBar::Separator->new,
     combobox  => SL::Layout::ActionBar::ComboBox->new,
  }->{$descriptor} or die 'unknown descriptor';
}

# TODO: this necessary?
sub simple {
  my ($class, $data) = @_;

  my ($text, %params) = @$data;

  if ($params{submit}) {
    require SL::Layout::ActionBar::Submit;
    return SL::Layout::ActionBar::Submit->new(text => $text, params => \%params);
  }

  if ($params{function}) {
    require SL::Layout::ActionBar::ScriptButton;
    return SL::Layout::ActionBar::ScriptButton->new(text => $text, params => \%params);
  }

  if ($params{actions}) {
    require SL::Layout::ActionBar::ComboBox;
    return SL::Layout::ActionBar::ComboBox->new(text => $text, %params);
  }
}

# shortcut for presenter

sub p {
  SL::Presenter->get
}

# unique id to tie div and javascript together
sub init_id {
  $_[0]->p->name_to_id('action[]')
}


1;

__END__

=head 1

planned options for clickables:

- checks => [ ... ] (done)

a list of functions that need to return true before submitting

- submit => [ form-selector, { params } ] (done)

on click submit the form specified by form-selector with the additional params

- function => function-name (done)

on click call the specified function (is this a special case of checks?)

- disabled => true/false (done)

TODO:

- runtime disable/enable

