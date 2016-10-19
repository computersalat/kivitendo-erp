package SL::ShopConnector::Shopware;

use strict;

use parent qw(SL::ShopConnector::Base);

use SL::JSON;
use LWP::UserAgent;
use LWP::Authen::Digest;
use SL::DB::ShopOrder;
use SL::DB::ShopOrderItem;
use Data::Dumper;

use Rose::Object::MakeMethods::Generic (
  'scalar --get_set_init' => [ qw(connector url) ],
);

sub get_new_orders {
  my ($self, $id) = @_;

  my $url = $self->url;

  my $ordnumber = $self->config->last_order_number + 1;
  my $otf = $self->config->orders_to_fetch;

  my $i;
  for ($i=1;$i<=$otf;$i++) {
    my $data = $self->connector->get("http://$url/api/orders/$ordnumber?useNumberAsId=true");
    my $data_json = $data->content;
    my $import = SL::JSON::decode_json($data_json);
    if ($import->{success}){

      # Mapping to table shoporders. See http://community.shopware.com/_detail_1690.html#GET_.28Liste.29
      my %columns = (
        amount                  => $import->{data}->{invoiceAmount},
        billing_city            => $import->{data}->{billing}->{city},
        billing_company         => $import->{data}->{billing}->{company},
        billing_country         => $import->{data}->{billing}->{country}->{name},
        billing_department      => $import->{data}->{billing}->{department},
        billing_email           => $import->{data}->{customer}->{email},
        billing_fax             => $import->{data}->{billing}->{fax},
        billing_firstname       => $import->{data}->{billing}->{firstName},
        billing_greeting        => ($import->{data}->{billing}->{salutation} eq 'mr' ? 'Herr' : 'Frau'),
        billing_lastname        => $import->{data}->{billing}->{lastName},
        billing_phone           => $import->{data}->{billing}->{phone},
        billing_street          => $import->{data}->{billing}->{street},
        billing_vat             => $import->{data}->{billing}->{vatId},
        billing_zipcode         => $import->{data}->{billing}->{zipCode},
        customer_city           => $import->{data}->{billing}->{city},
        customer_company        => $import->{data}->{billing}->{company},
        customer_country        => $import->{data}->{billing}->{country}->{name},
        customer_department     => $import->{data}->{billing}->{department},
        customer_email          => $import->{data}->{customer}->{email},
        customer_fax            => $import->{data}->{billing}->{fax},
        customer_firstname      => $import->{data}->{billing}->{firstName},
        customer_greeting       => ($import->{data}->{billing}->{salutation} eq 'mr' ? 'Herr' : 'Frau'),
        customer_lastname       => $import->{data}->{billing}->{lastName},
        customer_phone          => $import->{data}->{billing}->{phone},
        customer_street         => $import->{data}->{billing}->{street},
        customer_vat            => $import->{data}->{billing}->{vatId},
        customer_zipcode        => $import->{data}->{billing}->{zipCode},
        customer_newsletter     => $import->{data}->{customer}->{newsletter},
        delivery_city           => $import->{data}->{shipping}->{city},
        delivery_company        => $import->{data}->{shipping}->{company},
        delivery_country        => $import->{data}->{shipping}->{country}->{name},
        delivery_department     => $import->{data}->{shipping}->{department},
        delivery_email          => "",
        delivery_fax            => $import->{data}->{shipping}->{fax},
        delivery_firstname      => $import->{data}->{shipping}->{firstName},
        delivery_greeting       => ($import->{data}->{shipping}->{salutation} eq 'mr' ? 'Herr' : 'Frau'),
        delivery_lastname       => $import->{data}->{shipping}->{lastName},
        delivery_phone          => $import->{data}->{shipping}->{phone},
        delivery_street         => $import->{data}->{shipping}->{street},
        delivery_vat            => $import->{data}->{shipping}->{vatId},
        delivery_zipcode        => $import->{data}->{shipping}->{zipCode},
        host                    => $import->{data}->{shop}->{hosts},
        netamount               => $import->{data}->{invoiceAmountNet},
        order_date              => $import->{data}->{orderTime},
        payment_description     => $import->{data}->{payment}->{description},
        payment_id              => $import->{data}->{paymentId},
        remote_ip               => $import->{data}->{remoteAddress},
        sepa_account_holder     => $import->{data}->{paymentIntances}->{accountHolder},
        sepa_bic                => $import->{data}->{paymentIntances}->{bic},
        sepa_iban               => $import->{data}->{paymentIntances}->{iban},
        shipping_costs          => $import->{data}->{invoiceShipping},
        shipping_costs_net      => $import->{data}->{invoiceShippingNet},
        shop_c_billing_id       => $import->{data}->{billing}->{customerId},
        shop_c_billing_number   => $import->{data}->{billing}->{number},
        shop_c_delivery_id      => $import->{data}->{shipping}->{id},
        shop_customer_id        => $import->{data}->{customerId},
        shop_customer_number    => $import->{data}->{billing}->{number},
        shop_customer_comment   => $import->{data}->{customerComment},
        shop_data               => "",
        shop_id                 => $import->{data}->{id},
        shop_ordernumber        => $import->{data}->{number},
        shop_trans_id           => $import->{data}->{id},
        tax_included            => ($import->{data}->{net} == 0 ? 0 : 1)
      );
      my $insert = SL::DB::ShopOrder->new(%columns);
      $insert->save;
      my $id = $insert->id;

      my @positions = sort { Sort::Naturally::ncmp($a->{"partnumber"}, $b->{"partnumber"}) } @{ $import->{data}->{details} };
      my $position = 1;
      foreach my $pos(@positions) {
        my %pos_columns = ( description       => $pos->{articleName},
                            partnumber        => $pos->{articleNumber},
                            price             => $pos->{price},
                            quantity          => $pos->{quantity},
                            position          => $position,
                            tax_rate          => $pos->{taxRate},
                            shop_trans_id     => $pos->{articleId},
                            shop_order_id     => $id,
                          );
        my $pos_insert = SL::DB::ShopOrderItem->new(%pos_columns);
        $pos_insert->save;
        $position++;
      }
      # Versandkosten als Position am ende einfügen Dreschflegelspezifisch event. konfigurierbar machen

      if (my $shipping = $import->{data}->{dispatch}->{name}) {
        my %shipping_partnumbers = (
                                    'Auslandsversand Einschreiben'  => { 'partnumber' => '900650'},
                                    'Auslandsversand'               => { 'partnumber' => '900650'},
                                    'Standard Versand'              => { 'partnumber' => '905500'},
                                    'Kostenloser Versand'           => { 'partnumber' => '905500'},
                                  );
        my %shipping_pos = ( description    => $import->{data}->{dispatch}->{name},
                             partnumber     => $shipping_partnumbers{$shipping}->{partnumber},
                             price          => $import->{data}->{invoiceShipping},
                             quantity       => 1,
                             position       => $position,
                             tax_rate       => 7,
                             shop_trans_id  => 0,
                             shop_order_id  => $id,
                           );
        my $shipping_pos_insert = SL::DB::ShopOrderItem->new(%shipping_pos);
        $shipping_pos_insert->save;

        my $attributes->{last_order_number} = $ordnumber;
        $self->config->assign_attributes( %{ $attributes } );
        $self->config->save;
        $ordnumber++;
      }
    }else{
      last;
    }
  }
  # return $import;
};

sub init_url {
  my ($self) = @_;
  # TODO: validate url and port
  $self->url($self->config->url . ":" . $self->config->port);
};

sub init_connector {
  my ($self) = @_;
  my $ua = LWP::UserAgent->new;
  $ua->credentials(
      $self->url,
      "Shopware REST-API",
      $self->config->login => $self->config->password
  );
  return $ua;
};

1;

__END__

=encoding utf-8

=head1 NAME

  SL::ShopConnecter::Shopware - connector for Shopware 5

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 BUGS

None yet. :)

=head1 AUTHOR


=cut
