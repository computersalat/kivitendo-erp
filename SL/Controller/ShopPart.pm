package SL::Controller::ShopPart;
#package SL::Controller::ShopPart;

use strict;

use parent qw(SL::Controller::Base);

use Data::Dumper;
use SL::Locale::String qw(t8);
use SL::DB::ShopPart;
use SL::DB::File;
use SL::Controller::FileUploader;
use SL::DB::Default;
use SL::Helper::Flash;

use Rose::Object::MakeMethods::Generic
(
   scalar                 => [ qw(price_sources) ],
  'scalar --get_set_init' => [ qw(shop_part file) ],
);

__PACKAGE__->run_before('check_auth');
__PACKAGE__->run_before('add_javascripts', only => [ qw(edit_popup) ]);
__PACKAGE__->run_before('load_pricesources',    only => [ qw(create_or_edit_popup) ]);

#
# actions
#

sub action_create_or_edit_popup {
  my ($self) = @_;

  $self->render_shop_part_edit_dialog();
};

sub action_update_shop {
  my ($self, %params) = @_;

  my $shop_part = SL::DB::Manager::ShopPart->find_by(id => $::form->{shop_part_id});
  die unless $shop_part;
  require SL::Shop;
  my $shop = SL::Shop->new( config => $shop_part->shop );

  # data to upload to shop. Goes to SL::Connector::XXXConnector.
  my $part_hash = $shop_part->part->as_tree;
  my $json      = SL::JSON::to_json($part_hash);
  my $return    = $shop->connector->update_part($self->shop_part, $json);

  # the connector deals with parsing/result verification, just needs to return success or failure
  if ( $return == 1 ) {
    my $now = DateTime->now;
    my $attributes->{last_update} = $now;
    $self->shop_part->assign_attributes(%{ $attributes });
    $self->shop_part->save;
    $self->js->html('#shop_part_last_update_' . $shop_part->id, $now->to_kivitendo('precision' => 'minute'))
           ->flash('info', t8("Updated part [#1] in shop [#2] at #3", $shop_part->part->displayable_name, $shop_part->shop->description, $now->to_kivitendo('precision' => 'minute') ) )
           ->render;
  } else {
    $self->js->flash('error', t8('The shop part wasn\'t updated.'))->render;
  };

};

sub action_show_files {
  my ($self) = @_;

  require SL::DB::File;
  my $images = SL::DB::Manager::File->get_all_sorted( where => [ trans_id => $::form->{id}, modul => $::form->{modul}, file_content_type => { like => 'image/%' } ], sort_by => 'position' );

  $self->render('shop_part/_list_images', { header => 0 }, IMAGES => $images);
}

sub action_ajax_upload_file{
  my ($self, %params) = @_;

  my $attributes                   = $::form->{ $::form->{form_prefix} } || die "Missing attributes";

  $attributes->{filename} = ((($::form->{ATTACHMENTS} || {})->{ $::form->{form_prefix} } || {})->{file_content} || {})->{filename};

  my @errors;
  my @file_errors = SL::DB::File->new(%{ $attributes })->validate;
  push @errors,@file_errors if @file_errors;

  my @type_error = SL::Controller::FileUploader->validate_filetype($attributes->{filename},$::form->{aft});
  push @errors,@type_error if @type_error;

  return $self->js->error(@errors)->render($self) if @errors;

  $self->file->assign_attributes(%{ $attributes });
  $self->file->file_update_type_and_dimensions;
  $self->file->save;

  $self->js
    ->dialog->close('#jqueryui_popup_dialog')
    ->run('kivi.shop_part.show_images',$self->file->trans_id)
    ->render();
}

sub action_ajax_update_file{
  my ($self, %params) = @_;

  my $attributes                   = $::form->{ $::form->{form_prefix} } || die "Missing attributes";

  if (!$attributes->{file_content}) {
    delete $attributes->{file_content};
  } else {
    $attributes->{filename} = ((($::form->{ATTACHMENTS} || {})->{ $::form->{form_prefix} } || {})->{file_content} || {})->{filename};
  }

  my @errors;
  my @type_error = SL::Controller::FileUploader->validate_filetype($attributes->{filename},$::form->{aft});
  push @errors,@type_error if @type_error;
  $self->file->assign_attributes(%{ $attributes });
  my @file_errors = $self->file->validate if $attributes->{file_content};;
  push @errors,@file_errors if @file_errors;


  return $self->js->error(@errors)->render($self) if @errors;

  $self->file->file_update_type_and_dimensions if $attributes->{file_content};
  $self->file->save;

  $self->js
    ->dialog->close('#jqueryui_popup_dialog')
    ->run('kivi.shop_part.show_images',$self->file->trans_id)
    ->render();
}

sub action_ajax_delete_file {
  my ( $self ) = @_;
  $self->file->delete;

  $self->js
    ->run('kivi.shop_part.show_images',$self->file->trans_id)
    ->render();
}

sub action_get_categories {
  my ($self) = @_;

  require SL::Shop;
  my $shop = SL::Shop->new( config => $self->shop_part->shop );
  my $categories = $shop->connector->get_categories;

  $self->js
    ->run(
      'kivi.shop_part.shop_part_dialog',
      t8('Shopcategories'),
      $self->render('shop_part/categories', { output => 0 }, CATEGORIES => $categories )
    )
    ->reinit_widgets;

  $self->js->render;
}

# old:
# sub action_edit {
#   my ($self) = @_;
#
#   $self->render('shop_part/edit'); #, { output => 0 }); #, price_source => $price_source)
# }
#
# used when saving existing ShopPart

sub action_update {
  my ($self) = @_;

  $self->create_or_update;
}

sub action_show_price_n_pricesource {
  my ($self) = @_;

  my ( $price, $price_src_str ) = $self->get_price_n_pricesource($::form->{pricesource});

  #TODO Price must be formatted. $price_src_str must be translated
  $self->js->html('#price_' . $self->shop_part->id, $price)
           ->html('#active_price_source_' . $self->shop_part->id, $price_src_str)
           ->render;
}

sub action_show_stock {
  my ($self) = @_;
  my ( $stock_local, $stock_onlineshop );

  require SL::Shop;
  my $shop = SL::Shop->new( config => $self->shop_part->shop );
  my $shop_article = $shop->connector->get_article($self->shop_part->part->partnumber);

  $stock_local = $self->shop_part->part->onhand;
  $stock_onlineshop = $shop_article->{data}->{mainDetail}->{inStock};

  $self->js->html('#stock_' . $self->shop_part->id, $stock_local."/".$stock_onlineshop)
           ->render;
}


sub create_or_update {
  my ($self) = @_;

  my $is_new = !$self->shop_part->id;

  # in edit.html all variables start with shop_part
  my $params = delete($::form->{shop_part}) || { };

  $self->shop_part->assign_attributes(%{ $params });

  $self->shop_part->save;

  my ( $price, $price_src_str ) = $self->get_price_n_pricesource($self->shop_part->active_price_source);

  #TODO Price must be formatted. $price_src_str must be translated
  flash('info', $is_new ? t8('The shop part has been created.') : t8('The shop part has been saved.'));
  # $self->js->val('#partnumber', 'ladida');
  $self->js->html('#shop_part_description_' . $self->shop_part->id, $self->shop_part->shop_description)
           ->html('#shop_part_active_' . $self->shop_part->id, $self->shop_part->active)
           ->html('#price_' . $self->shop_part->id, $price)
           ->html('#active_price_source_' . $self->shop_part->id, $price_src_str)
           ->run('kivi.shop_part.close_dialog')
           ->flash('info', t8("Updated shop part"))
           ->render;
}

sub render_shop_part_edit_dialog {
  my ($self) = @_;

  # when self->shop_part is called in template, it will be an existing shop_part with id,
  # or a new shop_part with only part_id and shop_id set
  $self->js
    ->run(
      'kivi.shop_part.shop_part_dialog',
      t8('Shop part'),
      $self->render('shop_part/edit', { output => 0 }) #, shop_part => $self->shop_part)
    )
    ->reinit_widgets;

  $self->js->render;
}

sub action_save_categories {
  my ($self) = @_;

  my @categories =  @{ $::form->{categories} || [] };
  $main::lxdebug->dump(0, 'WH: KATEGORIEN: ', \@categories);
  my @cat = ();
  foreach my $cat ( @categories) {
    # TODO das koma macht Probleme z.B kategorie "Feldsalat, Rapunzel"
    my @temp = [split(/,/,$cat)];
    push( @cat, @temp );
  }
  $main::lxdebug->dump(0, 'WH: KAT2:',\@cat);

  my $categories->{shop_category} = \@cat;

  my $params = delete($::form->{shop_part}) || { };

  $self->shop_part->assign_attributes(%{ $params });
  $self->shop_part->assign_attributes(%{ $categories });

  $self->shop_part->save;

  flash('info', t8('The categories has been saved.'));

  $self->js->run('kivi.shop_part.close_dialog')
           ->flash('info', t8("Updated categories"))
           ->render;
}

sub action_reorder {
  my ($self) = @_;
$main::lxdebug->message(0, "WH:REORDER ");
  require SL::DB::File;
  SL::DB::File->reorder_list(@{ $::form->{image_id} || [] });
  $main::lxdebug->message(0, "WH:REORDER II ");

  $self->render(\'', { type => 'json' });
}

#
# internal stuff
#
sub add_javascripts  {
  # is this needed?
  $::request->{layout}->add_javascripts(qw(kivi.shop_part.js));
}

sub load_pricesources {
  my ($self) = @_;

  # the price sources to use for the article: sellprice, lastcost,
  # listprice, or one of the pricegroups. It overwrites the default pricesource from the shopconfig.
  # TODO: implement valid pricerules for the article
  my $pricesources;
  push( @{ $pricesources } , { id => "master_data/sellprice", name => t8("Master Data")." - ".t8("Sellprice") },
                             { id => "master_data/listprice", name => t8("Master Data")." - ".t8("Listprice") },
                             { id => "master_data/lastcost",  name => t8("Master Data")." - ".t8("Lastcost") }
                             );
  my $pricegroups = SL::DB::Manager::Pricegroup->get_all;
  foreach my $pg ( @$pricegroups ) {
    push( @{ $pricesources } , { id => "pricegroup/".$pg->id, name => t8("Pricegroup") . " - " . $pg->pricegroup} );
  };

  $self->price_sources( $pricesources );
}

sub get_price_n_pricesource {
  my ($self,$pricesource) = @_;

  my ( $price_src_str, $price_src_id ) = split(/\//,$pricesource);

  require SL::DB::Pricegroup;
  require SL::DB::Part;
  #TODO Price must be formatted. Translations for $price_grp_str
  my $price;
  if ($price_src_str eq "master_data") {
    my $part = SL::DB::Manager::Part->get_all( where => [id => $self->shop_part->part_id], with_objects => ['prices'],limit => 1)->[0];
    $price = $part->$price_src_id;
    $price_src_str = $price_src_id;
  }else{
    my $part = SL::DB::Manager::Part->get_all( where => [id => $self->shop_part->part_id, 'prices.'.pricegroup_id => $price_src_id], with_objects => ['prices'],limit => 1)->[0];
    my $pricegrp = SL::DB::Manager::Pricegroup->find_by( id => $price_src_id )->pricegroup;
    $price =  $part->prices->[0]->price;
    $price_src_str = $pricegrp;
  }
  return($price,$price_src_str);
}

sub check_auth {
  return 1; # TODO: implement shop rights
  # $::auth->assert('shop');
}

sub init_shop_part {
  if ($::form->{shop_part_id}) {
    SL::DB::Manager::ShopPart->find_by(id => $::form->{shop_part_id});
  } else {
    SL::DB::ShopPart->new(shop_id => $::form->{shop_id}, part_id => $::form->{part_id});
  };
}

1;

__END__

=encoding utf-8


=head1 NAME

  SL::Controller::ShopPart - Controller for managing ShopParts

=head1 SYNOPSIS

  ShopParts are configured in a tab of the corresponding part.

=head1 FUNCTIONS


=over 4


=item C<action_update_shop>

  To be called from the "Update" button, for manually syncing a part with its shop. Generates a  Calls some ClientJS functions to modifiy original page.


=head1 AUTHORS

  G. Richardson E<lt>information@kivitendo-premium.deE<gt>
  W. Hahn E<lt>wh@futureworldsearch.netE<gt>

=cut

=cut
1;
