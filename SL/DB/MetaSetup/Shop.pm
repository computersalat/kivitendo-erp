# This file has been auto-generated. Do not modify it; it will be overwritten
# by rose_auto_create_model.pl automatically.
package SL::DB::Shop;
#package SL::DB::Shop;

use strict;

use base qw(SL::DB::Object);

__PACKAGE__->meta->table('shops');

__PACKAGE__->meta->columns(
  connector         => { type => 'text' },
  description       => { type => 'text' },
  id                => { type => 'serial', not_null => 1 },
  last_order_number => { type => 'integer' },
  login             => { type => 'text' },
  obsolete          => { type => 'boolean', default => 'false', not_null => 1 },
  orders_to_fetch   => { type => 'integer' },
  password          => { type => 'text' },
  port              => { type => 'integer' },
  price_source      => { type => 'text' },
  pricetype         => { type => 'text' },
  sortkey           => { type => 'integer' },
  taxzone_id        => { type => 'integer' },
  url               => { type => 'text' },
);

__PACKAGE__->meta->primary_key_columns([ 'id' ]);

1;
;
