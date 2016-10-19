package SL::ShopConnector::Shopware;
#package SL::ShopConnector::Shopware;
#package SL::ShopConnector::Shopware;

use strict;

use parent qw(SL::ShopConnector::Base);

use SL::DBUtils;
use SL::JSON;
use LWP::UserAgent;
use LWP::Authen::Digest;
use SL::DB::ShopOrder;
use SL::DB::ShopOrderItem;
use Data::Dumper;
use Sort::Naturally ();
use SL::Helper::Flash;
use Encode qw(encode_utf8);

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
        shop_id                 => $self->config->id,
        shop_ordernumber        => $import->{data}->{number},
        shop_trans_id           => $import->{data}->{id},
        tax_included            => ($import->{data}->{net} == 0 ? 0 : 1)
      );
      my $shop_order = SL::DB::ShopOrder->new(%columns);

      $shop_order->save;
      my $id = $shop_order->id;

      my @positions = sort { Sort::Naturally::ncmp($a->{"partnumber"}, $b->{"partnumber"}) } @{ $import->{data}->{details} };
      my $position = 1;
      foreach my $pos(@positions) {
        my $price = $::form->round_amount($pos->{price},2);

        my %pos_columns = ( description       => $pos->{articleName},
                            partnumber        => $pos->{articleNumber},
                            price             => $price,
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
      $shop_order->{positions} = $position;

      # Only Customers which are not found will be applied
      my $proposals = SL::DB::Manager::Customer->get_all_count(
           where => [
                       or => [
                                and => [ # when matching names also match zipcode
                                         or => [ 'name' => { like => "$shop_order->billing_lastname"},
                                                 'name' => { like => $shop_order->billing_company },
                                               ],
                                         'zipcode' => { like => $shop_order->billing_zipcode },
                                       ],
                                or  => [ 'email' => { like => $shop_order->billing_email } ],
                                and  => [ 'street' => { like => $shop_order->billing_street },
                                         'zipcode' => { like => $shop_order->billing_zipcode } ],
                             ],
                    ],
      );

      if(!$proposals){
        my %address = ( 'name'                  => $shop_order->billing_firstname . " " . $shop_order->billing_lastname,
                        'department_1'          => $shop_order->billing_company,
                        'department_2'          => $shop_order->billing_department,
                        'street'                => $shop_order->billing_street,
                        'zipcode'               => $shop_order->billing_zipcode,
                        'city'                  => $shop_order->billing_city,
                        'email'                 => $shop_order->billing_email,
                        'country'               => $shop_order->billing_country,
                        'greeting'              => $shop_order->billing_greeting,
                        'fax'                   => $shop_order->billing_fax,
                        'phone'                 => $shop_order->billing_phone,
                        'ustid'                 => $shop_order->billing_vat,
                        'taxincluded_checked'   => 1,   # TODO hardcoded
                        'taxincluded'           => 1,   # TODO hardcoded
                        'klass'                 => 908, # TODO hardcoded
                        'taxzone_id'            => 4,   # TODO hardcoded, use default taxzone instead
                        'currency'              => 1,   # TODO hardcoded
                        'payment_id'            => 7345,# TODO hardcoded
                      );
        my $customer = SL::DB::Customer->new(%address);
        $customer->save;

      }
      my %billing_address = ( 'name'     => $shop_order->billing_lastname,
                              'company'  => $shop_order->billing_company,
                              'street'   => $shop_order->billing_street,
                              'zipcode'  => $shop_order->billing_zipcode,
                              'city'     => $shop_order->billing_city,
                            );
      my $b_address = SL::Controller::ShopOrder->check_address(%billing_address);
      if ($b_address) {
        $shop_order->{kivi_customer_id} = $b_address->{id};
      }
      $shop_order->save;

      # DF Versandkosten als Position am ende einfügen Dreschflegelspezifisch event. konfigurierbar machen
      if (my $shipping = $import->{data}->{dispatch}->{name}) {
        my %shipping_partnumbers = (
                                    'Auslandsversand Einschreiben'  => { 'partnumber' => '900650'},
                                    'Auslandsversand'               => { 'partnumber' => '900650'},
                                    'Versandpauschale Inland'       => { 'partnumber' => '905500'},
                                    'Kostenloser Versand'           => { 'partnumber' => '905500'},
                                  );
        # TODO description für Preis muss angepasst werden
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

      }
        my $attributes->{last_order_number} = $ordnumber;
        $self->config->assign_attributes( %{ $attributes } );
        $self->config->save;
        $ordnumber++;
      # EOT Versandkosten DF
    }
  }
    my $shop = $self->config->description;

    my @fetched_orders = ($shop,$i);

    return \@fetched_orders;
};

sub get_categories {
  my ($self) = @_;

  my $url = $self->url;

  my $data = $self->connector->get("http://$url/api/categories");
  my $data_json = $data->content;
  my $import = SL::JSON::decode_json($data_json);
  my @daten = @{$import->{data}};
  my %categories = map { ($_->{id} => $_) } @daten;

  for(@daten) {
    my $parent = $categories{$_->{parentId}};
    $parent->{children} ||= [];
    push @{$parent->{children}},$_;
  }

  return \@daten;
}

sub update_part {
  my ($self, $shop_part, $json) = @_;

  #shop_part is passed as a param
  die unless ref($shop_part) eq 'SL::DB::ShopPart';

  my $url = $self->url;
  my $part = SL::DB::Part->new(id => $shop_part->{part_id})->load;

  # TODO: Prices (pricerules, pricegroups, multiple prices)
  my $cvars = { map { ($_->config->name => { value => $_->value_as_text, is_valid => $_->is_valid }) } @{ $part->cvars_by_config } };

  my @cat = ();
  foreach my $row_cat ( @{ $shop_part->shop_category } ) {
    my $temp = { ( id => @{$row_cat}[0], ) };
    push ( @cat, $temp );
  }

  my $images = SL::DB::Manager::File->get_all( where => [ modul => 'shop_part', trans_id => $part->{id} ]);
  my @upload_img = ();
  foreach my $img (@{ $images }) {
    my ($path, $extension) = (split /\./, $img->{filename});
    my $temp ={ ( link        => 'data:' . $img->{file_content_type} . ';base64,' . MIME::Base64::encode($img->{file_content},''),
                  description => $img->{title},
                  position    => $img->{position},
                  extension   => $extension,
                      )}    ;
    push( @upload_img, $temp);
  }

  my ($import,$data,$data_json);
  if( $shop_part->last_update){
    my $partnumber = $::form->escape($part->{partnumber});#shopware don't accept "/" in articlenumber
    $data = $self->connector->get("http://$url/api/articles/$partnumber?useNumberAsId=true");
    $data_json = $data->content;
    $import = SL::JSON::decode_json($data_json);
  }

  # get the right price
  my ( $price_src_str, $price_src_id ) = split(/\//,$shop_part->active_price_source);
  require SL::DB::Part;
  my $price;
  if ($price_src_str eq "master_data") {
    my $part = SL::DB::Manager::Part->get_all( where => [id => $shop_part->part_id], with_objects => ['prices'],limit => 1)->[0];
    $price = $part->$price_src_id;
  }else{
    my $part = SL::DB::Manager::Part->get_all( where => [id => $shop_part->part_id, 'prices.'.pricegroup_id => $price_src_id], with_objects => ['prices'],limit => 1)->[0];
    $price =  $part->prices->[0]->price;
  }

  # get the right taxrate for the article
  my $taxrate;
  my $dbh = $::form->get_standard_dbh();
  my $b_id = $part->buchungsgruppen_id;
  my $t_id = $shop_part->shop->taxzone_id;

  my $sql_str = "SELECT a.rate AS taxrate from tax a
  WHERE a.taxkey = (SELECT b.taxkey_id
  FROM chart b LEFT JOIN taxzone_charts c ON b.id = c.income_accno_id
  WHERE c.taxzone_id = $t_id
  AND c.buchungsgruppen_id = $b_id)";

  my $rate = selectall_hashref_query($::form, $dbh, $sql_str);
  $taxrate = @$rate[0]->{taxrate}*100;

  # mapping to shopware still missing attributes,metatags
  my %shop_data =  (  name              => $part->{description},
                      tax               => $taxrate,
                      mainDetail        => { number   => $part->{partnumber},
                                         inStock  => $part->{onhand},
                                         prices   =>  [ {          from   => 1,
                                                                   price  => $price,
                                                        customerGroupKey  => 'EK',
                                                      },
                                                    ],
                                       },
                      supplier          => $cvars->{freifeld_7}->{value},
                      descriptionLong   => $shop_part->{shop_description},
                      active            => $shop_part->active,
                      images            => [ @upload_img ],
                      __options_images  => { replace => 1, },
                      categories        => [ @cat ],
                      description       => $shop_part->{shop_description},
                      active            => $shop_part->active,
                      images            => [ @upload_img ],
                      __options_images  => { replace => 1, },
                      categories        => [ @cat ], #{ path => 'Deutsch|test2' }, ], #[ $categories ],

                    )
                  ;
  my $dataString = SL::JSON::to_json(\%shop_data);
  $dataString = encode_utf8($dataString);

  my $upload_content;
  if($import->{success}){
  my %del_img =  ( images        => [ {} ], ) ;
  my $del_imgString = SL::JSON::to_json(\%del_img);
  #my $delImg = $self->connector->put("http://$url/api/articles/$part->{partnumber}?useNumberAsId=true",Content => $del_imgString);
    #update
    my $partnumber = $::form->escape($part->{partnumber});#shopware dosn't accept / in articlenumber
    my $upload = $self->connector->put("http://$url/api/articles/$partnumber?useNumberAsId=true",Content => $dataString);
    my $data_json = $upload->content;
    $upload_content = SL::JSON::decode_json($data_json);
  }else{
    #upload
    my $upload = $self->connector->post("http://$url/api/articles/",Content => $dataString);
    my $data_json = $upload->content;
    $upload_content = SL::JSON::decode_json($data_json);
  }
  if(@upload_img) {
    my $partnumber = $::form->escape($part->{partnumber});#shopware don't accept / in articlenumber
    $self->connector->put("http://$url/api/generateArticleImages/$partnumber?useNumberAsId=true");
  }
  return $upload_content->{success};
}

sub get_article {
  my ($self,$partnumber) = @_;

  my $url = $self->url;
  my $data = $self->connector->get("http://$url/api/articles/$partnumber?useNumberAsId=true");
  my $data_json = $data->content;
  return SL::JSON::decode_json($data_json);
}

sub init_url {
  my ($self) = @_;
  # TODO: validate url and port Mabey in shopconfig test connection
  $self->url($self->config->url . ":" . $self->config->port);
};

sub init_connector {
  my ($self) = @_;
  my $ua = LWP::UserAgent->new;
  $ua->credentials(
      $self->url,
      "Shopware REST-API", # TODO in config
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

  W. Hahn E<lt>wh@futureworldsearch.netE<gt>

=cut
