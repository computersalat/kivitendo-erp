package SL::DB::Manager::PartsClassification;

use strict;

use parent qw(SL::DB::Helper::Manager);
use SL::DB::Helper::Sorted;

sub object_class { 'SL::DB::PartsClassification' }

__PACKAGE__->make_manager_methods;

#
# get the one/two character shortcut of the parts classification
#
sub get_abbreviation {
  my ($class,$id) = @_;
  my $obj = $class->get_first(query => [ id => $id ]);
  return '' unless $obj;
  return $obj->abbreviation?$obj->abbreviation:'';
}

#
# get the one/two character shortcut of the parts classification if itis a separate article
#
sub get_separate_abbreviation {
  my ($class,$id) = @_;
  my $obj = $class->get_first(query => [ id => $id ]);
  return '' unless $obj;
  return $obj->report_separate?$obj->abbreviation:'';
}

sub get_separate_abbreviation {
  my ($class,$id) = @_;
  my $obj = $class->get_first(query => [ id => $id ]);
  return $obj->report_separate?$obj->abbreviation:'';
}

1;


__END__

=encoding utf-8

=head1 NAME

SL::DB::Manager::PartsClassification


=head1 SYNOPSIS

This class has wrapper methodes to get the shortcuts

=head1 METHODS

=head2 get_abbreviation

 $class->get_abbreviation($classification_id);

get the one/two character shortcut of the parts classification

=head2 get_separate_abbreviation

 $class->get_separate_abbreviation($classification_id);

get the one/two character shortcut of the parts classification if it is a separate article

=head1 AUTHOR

Martin Helmling E<lt>martin.helmling@opendynamic.deE<gt>

=cut

