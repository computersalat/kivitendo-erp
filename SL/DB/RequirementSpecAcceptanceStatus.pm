package SL::DB::RequirementSpecAcceptanceStatus;

use strict;

use SL::DB::MetaSetup::RequirementSpecAcceptanceStatus;
use SL::DB::Manager::RequirementSpecAcceptanceStatus;
use SL::DB::Helper::ActsAsList;
use SL::Locale::String;

sub validate {
  my ($self) = @_;

  my @errors;
  push @errors, t8('The description is missing.') if !$self->description;

  return @errors;
}

1;
