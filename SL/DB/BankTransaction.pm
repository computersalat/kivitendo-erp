# This file has been auto-generated only because it didn't exist.
# Feel free to modify it at will; it will not be overwritten automatically.

package SL::DB::BankTransaction;

use strict;

use SL::DB::MetaSetup::BankTransaction;
use SL::DB::Manager::BankTransaction;
use SL::DB::Helper::LinkedRecords;

require SL::DB::Invoice;
require SL::DB::PurchaseInvoice;

__PACKAGE__->meta->initialize;


# Creates get_all, get_all_count, get_all_iterator, delete_all and update_all.
#__PACKAGE__->meta->make_manager_class;

sub compare_to {
  my ($self, $other) = @_;

  return  1 if  $self->transdate && !$other->transdate;
  return -1 if !$self->transdate &&  $other->transdate;

  my $result = 0;
  $result    = $self->transdate <=> $other->transdate if $self->transdate;
  return $result || ($self->id <=> $other->id);
}

sub linked_invoices {
  my ($self) = @_;

  #my $record_links = $self->linked_records(direction => 'both');

  my @linked_invoices;

  my $record_links = SL::DB::Manager::RecordLink->get_all(where => [ from_table => 'bank_transactions', from_id => $self->id ]);

  foreach my $record_link (@{ $record_links }) {
    push @linked_invoices, SL::DB::Manager::Invoice->find_by(id => $record_link->to_id)->invnumber         if $record_link->to_table eq 'ar';
    push @linked_invoices, SL::DB::Manager::PurchaseInvoice->find_by(id => $record_link->to_id)->invnumber if $record_link->to_table eq 'ap';
  }

  return [ @linked_invoices ];
}

sub get_agreement_with_invoice {
  my ($self, $invoice) = @_;

  die "first argument is not an invoice object"
    unless ref($invoice) eq 'SL::DB::Invoice' or ref($invoice) eq 'SL::DB::PurchaseInvoice';

  my %points = (
    cust_vend_name_in_purpose   => 1,
    cust_vend_number_in_purpose => 1,
    datebonus0                  => 3,
    datebonus14                 => 2,
    datebonus35                 => 1,
    datebonus120                => 0,
    datebonus_negative          => -1,
    depositor_matches           => 2,
    exact_amount                => 4,
    exact_open_amount           => 4,
    invnumber_in_purpose        => 2,
    # overpayment                 => -1, # either other invoice is more likely, or several invoices paid at once
    payment_before_invoice      => -2,
    payment_within_30_days      => 1,
    remote_account_number       => 3,
    skonto_exact_amount         => 5,
    wrong_sign                  => -1,
  );

  my ($agreement,$rule_matches);

  # compare banking arrangements
  my ($iban, $bank_code, $account_number);
  $bank_code      = $invoice->customer->bank_code      if $invoice->is_sales;
  $account_number = $invoice->customer->account_number if $invoice->is_sales;
  $iban           = $invoice->customer->iban           if $invoice->is_sales;
  $bank_code      = $invoice->vendor->bank_code        if ! $invoice->is_sales;
  $iban           = $invoice->vendor->iban             if ! $invoice->is_sales;
  $account_number = $invoice->vendor->account_number   if ! $invoice->is_sales;
  if ( $bank_code eq $self->remote_bank_code && $account_number eq $self->remote_account_number ) {
    $agreement += $points{remote_account_number};
    $rule_matches .= 'remote_account_number(' . $points{'remote_account_number'} . ') ';
  };
  if ( $iban eq $self->remote_account_number ) {
    $agreement += $points{remote_account_number};
    $rule_matches .= 'remote_account_number(' . $points{'remote_account_number'} . ') ';
  };

  my $datediff = $self->transdate->{utc_rd_days} - $invoice->transdate->{utc_rd_days};
  $invoice->{datediff} = $datediff;

  # compare amount
  if (abs(abs($invoice->amount) - abs($self->amount)) < 0.01) {
    $agreement += $points{exact_amount};
    $rule_matches .= 'exact_amount(' . $points{'exact_amount'} . ') ';
  };

  # compare open amount, preventing double points when open amount = invoice amount
  if ( $invoice->amount != $invoice->open_amount && abs(abs($invoice->open_amount) - abs($self->amount)) < 0.01) {
    $agreement += $points{exact_open_amount};
    $rule_matches .= 'exact_open_amount(' . $points{'exact_open_amount'} . ') ';
  };

  if ( $invoice->skonto_date && abs(abs($invoice->amount_less_skonto) - abs($self->amount)) < 0.01) {
    $agreement += $points{skonto_exact_amount};
    $rule_matches .= 'skonto_exact_amount(' . $points{'skonto_exact_amount'} . ') ';
  };

  #search invoice number in purpose
  my $invnumber = $invoice->invnumber;
  # invnumbernhas to have at least 3 characters
  if ( length($invnumber) > 2 && $self->purpose =~ /\b$invnumber\b/i ) {
    $agreement += $points{invnumber_in_purpose};
    $rule_matches .= 'invnumber_in_purpose(' . $points{'invnumber_in_purpose'} . ') ';
  };

  #check sign
  if ( $invoice->is_sales && $self->amount < 0 ) {
    $agreement += $points{wrong_sign};
    $rule_matches .= 'wrong_sign(' . $points{'wrong_sign'} . ') ';
  };
  if ( ! $invoice->is_sales && $self->amount > 0 ) {
    $agreement += $points{wrong_sign};
    $rule_matches .= 'wrong_sign(' . $points{'wrong_sign'} . ') ';
  };

  # search customer/vendor number in purpose
  my $cvnumber;
  $cvnumber = $invoice->customer->customernumber if $invoice->is_sales;
  $cvnumber = $invoice->vendor->vendornumber     if ! $invoice->is_sales;
  if ( $cvnumber && $self->purpose =~ /\b$cvnumber\b/i ) {
    $agreement += $points{cust_vend_number_in_purpose};
    $rule_matches .= 'cust_vend_number_in_purpose(' . $points{'cust_vend_number_in_purpose'} . ') ';
  }

  # search for customer/vendor name in purpose (may contain GMBH, CO KG, ...)
  my $cvname;
  $cvname = $invoice->customer->name if $invoice->is_sales;
  $cvname = $invoice->vendor->name   if ! $invoice->is_sales;
  if ( $cvname && $self->purpose =~ /\b$cvname\b/i ) {
    $agreement += $points{cust_vend_name_in_purpose};
    $rule_matches .= 'cust_vend_name_in_purpose(' . $points{'cust_vend_name_in_purpose'} . ') ';
  };

  # compare depositorname, don't try to match empty depositors
  my $depositorname;
  $depositorname = $invoice->customer->depositor if $invoice->is_sales;
  $depositorname = $invoice->vendor->depositor   if ! $invoice->is_sales;
  if ( $depositorname && $self->remote_name =~ /$depositorname/ ) {
    $agreement += $points{depositor_matches};
    $rule_matches .= 'depositor_matches(' . $points{'depositor_matches'} . ') ';
  };

  #Check if words in remote_name appear in cvname
  my $check_string_points = _check_string($self->remote_name,$cvname);
  if ( $check_string_points ) {
    $agreement += $check_string_points;
    $rule_matches .= 'remote_name(' . $check_string_points . ') ';
  };

  # transdate prefilter: compare transdate of bank_transaction with transdate of invoice
  if ( $datediff < -5 ) { # this might conflict with advance payments
    $agreement += $points{payment_before_invoice};
    $rule_matches .= 'payment_before_invoice(' . $points{'payment_before_invoice'} . ') ';
  };
  if ( $datediff < 30 ) {
    $agreement += $points{payment_within_30_days};
    $rule_matches .= 'payment_within_30_days(' . $points{'payment_within_30_days'} . ') ';
  };

  # only if we already have a good agreement, let date further change value of agreement.
  # this is so that if there are several plausible open invoices which are all equal
  # (rent jan, rent feb...) the one with the best date match is chosen over
  # the others

  # another way around this is to just pre-filter by periods instead of matching everything
  if ( $agreement > 5 ) {
    if ( $datediff == 0 ) {
      $agreement += $points{datebonus0};
      $rule_matches .= 'datebonus0(' . $points{'datebonus0'} . ') ';
    } elsif  ( $datediff > 0 and $datediff <= 14 ) {
      $agreement += $points{datebonus14};
      $rule_matches .= 'datebonus14(' . $points{'datebonus14'} . ') ';
    } elsif  ( $datediff >14 and $datediff < 35) {
      $agreement += $points{datebonus35};
      $rule_matches .= 'datebonus35(' . $points{'datebonus35'} . ') ';
    } elsif  ( $datediff >34 and $datediff < 120) {
      $agreement += $points{datebonus120};
      $rule_matches .= 'datebonus120(' . $points{'datebonus120'} . ') ';
    } elsif  ( $datediff < 0 ) {
      $agreement += $points{datebonus_negative};
      $rule_matches .= 'datebonus_negative(' . $points{'datebonus_negative'} . ') ';
    } else {
  # e.g. datediff > 120
    };
  };

  return ($agreement,$rule_matches);
};

sub _check_string {
    my $bankstring = shift;
    my $namestring = shift;
    return 0 unless $bankstring and $namestring;

    my @bankwords = grep(/^\w+$/, split(/\b/,$bankstring));

    my $match = 0;
    foreach my $bankword ( @bankwords ) {
        # only try to match strings with more than 2 characters
        next unless length($bankword)>2;
        if ( $namestring =~ /\b$bankword\b/i ) {
            $match++;
        };
    };
    return $match;
};

1;

__END__

=pod

=head1 NAME

SL::DB::BankTransaction

=head1 FUNCTIONS

=over 4

=item C<get_agreement_with_invoice $invoice>

Using a point system this function checks whether the bank transaction matches
an invoices, using a variety of tests, such as

=over 2

=item * amount

=item * amount_less_skonto

=item * payment date

=item * invoice number in purpose

=item * customer or vendor name in purpose

=item * account number matches account number of customer or vendor

=back

The total number of points, and the rules that matched, are returned.

Example:
  my $bt      = SL::DB::Manager::BankTransaction->find_by(id => 522);
  my $invoice = SL::DB::Manager::Invoice->find_by(invnumber => '198');
  my ($agreement,rule_matches) = $bt->get_agreement_with_invoice($invoice);

=back

=head1 AUTHOR

G. Richardson E<lt>grichardson@kivitendo-premium.de<gt>

=cut
